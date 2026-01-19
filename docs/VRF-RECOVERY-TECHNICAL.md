# VRF Recovery System - Technical Documentation

## Overview

The Raffl Protocol implements a comprehensive recovery system with a **two-step VRF process** to handle Chainlink VRF
failures and prevent permanent fund lock-up. This document provides technical details for developers integrating with or
maintaining the protocol.

**Key Innovation**: Separation of winner selection from reward dispersal to protect against VRF callback gas limit
failures.

---

## Table of Contents

1. [Architecture](#architecture)
2. [Two-Step VRF Process](#two-step-vrf-process)
3. [VRF Request Lifecycle](#vrf-request-lifecycle)
4. [Recovery Mechanisms](#recovery-mechanisms)
5. [Smart Contract Interface](#smart-contract-interface)
6. [Integration Guide](#integration-guide)
7. [Monitoring & Automation](#monitoring--automation)
8. [Security Considerations](#security-considerations)

---

## Architecture

### Game Status Enum

```solidity
enum GameStatus {
    Initialized,   // 0: Raffle created, accepting entries
    FailedDraw,    // 1: Deadline passed, criteria not met
    DrawStarted,   // 2: VRF requested, waiting for random number
    WinnerDrawn,   // 3: Winner selected, awaiting reward dispersal ← NEW
    SuccessDraw    // 4: Rewards dispersed, raffle complete
}
```

### VRF Status Enum

```solidity
enum VRFStatus {
    None,       // No VRF request made
    Pending,    // VRF request made, awaiting response
    Fulfilled,  // VRF successfully fulfilled
    Failed      // VRF failed or timed out
}
```

### VRF Request Tracking

```solidity
struct VRFRequest {
    uint256 requestId;      // Chainlink VRF request ID
    uint256 requestTime;    // Timestamp when request was made
    VRFStatus status;       // Current status
}

mapping(address => VRFRequest) internal _raffleVRFRequests;
```

### Raffle Winner Storage

```solidity
contract Raffl {
    uint256 public winningEntry;    // The winning entry number
    address public winner;          // The address of the winner
    uint256 public requestId;       // The VRF request ID
    GameStatus public gameStatus;   // Current game state
}
```

### Constants

```solidity
uint256 public constant VRF_REQUEST_TIMEOUT = 24 hours;
```

---

## Two-Step VRF Process

### Why Two Steps?

**Problem**: VRF callbacks have strict gas limits and can fail during:

- Complex prize transfers (multiple NFTs, tokens)
- Large pool distributions
- High gas price scenarios
- Reentrancy scenarios

**Solution**: Separate winner selection (low gas) from reward dispersal (no limits)

### Flow Diagram

```
┌─────────────────────────────────────────────────────────────┐
│  STEP 1: WINNER SELECTION (VRF Callback)                   │
│  Gas Limited: ~500k gas                                      │
│  Critical: Must succeed                                      │
├─────────────────────────────────────────────────────────────┤
│  fulfillRandomWords()                                        │
│    ├─ Calculate winner from random number                   │
│    ├─ Store winner address                                  │
│    ├─ Store winning entry                                   │
│    ├─ Update status to WinnerDrawn                          │
│    └─ Emit WinnerDrawn event                                │
│  ✅ Low gas, unlikely to fail                                │
└─────────────────────────────────────────────────────────────┘
                            ↓
┌─────────────────────────────────────────────────────────────┐
│  STEP 2: REWARD DISPERSAL (Separate Transaction)           │
│  No Gas Limit                                                │
│  Permissionless: Anyone can trigger                          │
├─────────────────────────────────────────────────────────────┤
│  disperseRewards()                                           │
│    ├─ Transfer prizes to winner                             │
│    ├─ Transfer pool to creator/recipients                   │
│    ├─ Update status to SuccessDraw                          │
│    ├─ Emit RewardsDispersed event                           │
│    └─ Remove from active raffles                            │
│  ✅ Can retry if fails, no funds locked                      │
└─────────────────────────────────────────────────────────────┘
```

### State Transitions

```
Initialized → DrawStarted → WinnerDrawn → SuccessDraw
     ↓              ↓              ↓
FailedDraw    (VRF Retry)   (Manual Dispersal)
```

---

## VRF Request Lifecycle

### Complete Lifecycle

```
┌──────────────┐
│ Initialized  │ Raffle created
└──────┬───────┘
       │
       │ Deadline passes, criteria met
       │ performUpkeep() called
       ↓
┌──────────────┐
│ DrawStarted  │ VRF requested
└──────┬───────┘
       │
       ├──→ VRF fulfills (normal) ──→┐
       │                              │
       ├──→ Retry (stuck) ─────────→ │
       │                              │
       └──→ Emergency fail (24h+) ──→┤
                                      │
                              ┌───────↓────────┐
                              │  WinnerDrawn   │ Winner known
                              └───────┬────────┘
                                      │
                              ┌───────↓────────┐
                              │ Dispersal Path │
                              └───────┬────────┘
                                      │
       ┌──────────────────────────────┼──────────────────────────────┐
       │                              │                              │
       │                              │                              │
┌──────↓──────┐              ┌────────↓─────┐              ┌────────↓─────┐
│ Automation  │              │   Manual     │              │  Emergency   │
│ Dispersal   │              │  Dispersal   │              │    Fail      │
└──────┬──────┘              └──────┬───────┘              └──────┬───────┘
       │                            │                              │
       └────────────┬───────────────┘                              │
                    ↓                                               ↓
            ┌───────────────┐                              ┌───────────────┐
            │ SuccessDraw   │                              │  FailedDraw   │
            └───────────────┘                              └───────────────┘
             Winner receives                                Users get refunds
             prizes & pool                                  Creator gets prizes
```

### Detailed State Machine

#### State 1: Initialized → DrawStarted

**Trigger**: `performUpkeep()` after deadline

**Conditions**:

- Deadline passed
- Minimum entries met
- Upkeep not already performed

**Actions**:

```solidity
// Request VRF
uint256 requestId = s_vrfCoordinator.requestRandomWords(...);

// Store VRF request info
_raffleVRFRequests[raffle] = VRFRequest({
    requestId: requestId,
    requestTime: block.timestamp,
    status: VRFStatus.Pending
});

// Update raffle status
IRaffl(raffle).setSuccessCriteria(requestId);
```

#### State 2: DrawStarted → WinnerDrawn

**Trigger**: `fulfillRandomWords()` from VRF Coordinator

**Process**:

```solidity
function fulfillRandomWords(uint256 requestId, uint256[] calldata randomWords) internal override {
    address raffle = _requestIds[requestId];

    // Mark VRF as fulfilled
    _raffleVRFRequests[raffle].status = VRFStatus.Fulfilled;

    // Set winner (low gas operation)
    IRaffl(raffle).setWinner(requestId, randomWords[0]);
    // Note: Raffle stays in active list for dispersal
}
```

**Raffle Contract**:

```solidity
function setWinner(uint256 _requestId, uint256 randomNumber) external override onlyFactory {
    uint256 totalEntries_ = totalEntries();
    uint256 _winningEntry = randomNumber % totalEntries_;
    address _winner = ownerOf(_winningEntry);

    requestId = _requestId;
    winningEntry = _winningEntry;
    winner = _winner;
    gameStatus = GameStatus.WinnerDrawn;

    emit WinnerDrawn(_requestId, _winningEntry, _winner, totalEntries_);
}
```

**Gas Usage**: ~50-80k gas (very safe for VRF callback)

#### State 3: WinnerDrawn → SuccessDraw

**Trigger**: Any of:

1. Chainlink Automation via `performUpkeep()`
2. Manual call to `rafflFactory.disperseRewards(raffle)`
3. Direct call to `raffl.disperseRewards()`

**Process**:

```solidity
function disperseRewards() external override nonReentrant {
    if (gameStatus != GameStatus.WinnerDrawn) revert Errors.WinnerNotDrawn();

    _transferPrizes(winner);
    _transferPool();

    gameStatus = GameStatus.SuccessDraw;

    emit RewardsDispersed(winner);
}
```

**Gas Usage**: Variable (depends on prizes, no limit)

---

## Recovery Mechanisms

### Mechanism 1: Retry VRF Request

**Function**: `retryVRFRequest(address raffle)`

**Purpose**: Request new random words if VRF stuck

**Access**: Permissionless

**When to Use**:

- VRF hasn't responded (< 24 hours)
- Chainlink subscription funded
- Want to avoid emergency fail

**Process**:

```solidity
function retryVRFRequest(address raffle) external {
    if (!_raffles[raffle]) revert Errors.InvalidVRFRequest();

    VRFRequest storage vrfRequest = _raffleVRFRequests[raffle];
    if (vrfRequest.status != VRFStatus.Pending) revert Errors.VRFRequestNotPending();

    // Request new random words
    uint256 requestId = s_vrfCoordinator.requestRandomWords(...);

    // Update tracking
    _requestIds[requestId] = raffle;
    vrfRequest.requestId = requestId;
    vrfRequest.requestTime = block.timestamp;

    emit VRFRequestRetried(raffle, requestId);
}
```

### Mechanism 2: Manual Reward Dispersal

**Function**: `disperseRewards(address raffle)`

**Purpose**: Complete raffle after winner drawn

**Access**: Permissionless

**When to Use**:

- Winner drawn but automation delayed
- Want to manually complete raffle
- Automation failed/stuck

**Process**:

```solidity
function disperseRewards(address raffle) external {
    if (!_raffles[raffle]) revert Errors.InvalidVRFRequest();
    if (!IRaffl(raffle).shouldDisperseRewards()) revert Errors.UpkeepConditionNotMet();

    IRaffl(raffle).disperseRewards();
    _removeRaffleFromActive(raffle);
}
```

**Gas Estimate**: ~300-500k (depends on prizes)

### Mechanism 3: Emergency Fail

**Function**: `emergencyFailRaffle(address raffle)`

**Purpose**: Mark raffle as failed after timeout

**Access**: Permissionless (after 24h)

**When to Use**:

- 24+ hours since VRF request
- Multiple retries failed
- Need immediate resolution

**Process**:

```solidity
function emergencyFailRaffle(address raffle) external {
    if (!_raffles[raffle]) revert Errors.InvalidVRFRequest();

    VRFRequest storage vrfRequest = _raffleVRFRequests[raffle];
    if (vrfRequest.status != VRFStatus.Pending) revert Errors.VRFRequestNotPending();
    if (block.timestamp <= vrfRequest.requestTime + VRF_REQUEST_TIMEOUT)
        revert Errors.VRFRequestNotTimedOut();

    vrfRequest.status = VRFStatus.Failed;
    IRaffl(raffle).setFailedCriteria();
    _removeRaffleFromActive(raffle);

    emit RaffleEmergencyFailed(raffle);
}
```

---

## Smart Contract Interface

### New Functions in Raffl Contract

#### setWinner (Factory Only)

```solidity
function setWinner(uint256 _requestId, uint256 randomNumber) external override onlyFactory
```

**Purpose**: Store winner from VRF callback

**Access**: Factory only

**Gas**: ~50-80k

#### shouldDisperseRewards (View)

```solidity
function shouldDisperseRewards() external view override returns (bool)
```

**Returns**: `true` if winner drawn but rewards not dispersed

**Usage**: Check if raffle ready for dispersal

#### disperseRewards (Permissionless)

```solidity
function disperseRewards() external override nonReentrant
```

**Purpose**: Transfer prizes and pool to winners

**Access**: Anyone

**Gas**: Variable

#### New View Functions

```solidity
function winner() external view returns (address)
function winningEntry() external view returns (uint256)
function requestId() external view returns (uint256)
```

### Updated Functions in RafflFactory

#### fulfillRandomWords (Internal)

```solidity
function fulfillRandomWords(uint256 requestId, uint256[] calldata randomWords) internal override
```

**Changed**: Now only calls `setWinner()`, doesn't disperse rewards

#### checkUpkeep (View)

```solidity
function checkUpkeep(bytes calldata checkData) external view override
    returns (bool upkeepNeeded, bytes memory performData)
```

**Enhanced**: Now checks for both:

1. Raffles needing draw initiation
2. Raffles needing reward dispersal

#### performUpkeep (External)

```solidity
function performUpkeep(bytes calldata performData) external override
```

**Enhanced**: Handles both:

1. Starting draws
2. Dispersing rewards

#### New Public Function

```solidity
function disperseRewards(address raffle) external
```

**Purpose**: Manually trigger reward dispersal

**Access**: Permissionless

---

## Integration Guide

### For Frontend Developers

#### 1. Detect Raffle State

```javascript
async function getRaffleState(raffleAddress) {
  const raffle = new ethers.Contract(raffleAddress, RAFFL_ABI, provider);

  const gameStatus = await raffle.gameStatus();
  const shouldDisperse = await raffle.shouldDisperseRewards();
  const winner = await raffle.winner();

  const GameStatus = {
    Initialized: 0,
    FailedDraw: 1,
    DrawStarted: 2,
    WinnerDrawn: 3,
    SuccessDraw: 4,
  };

  return {
    status: gameStatus,
    statusName: Object.keys(GameStatus)[gameStatus],
    needsDispersal: shouldDisperse,
    winner: winner,
    isComplete: gameStatus === GameStatus.SuccessDraw,
  };
}
```

#### 2. Display Winner Before Dispersal

```javascript
async function displayWinnerInfo(raffleAddress) {
  const raffle = new ethers.Contract(raffleAddress, RAFFL_ABI, provider);

  if (await raffle.shouldDisperseRewards()) {
    const winner = await raffle.winner();
    const winningEntry = await raffle.winningEntry();

    console.log("Winner Selected!");
    console.log("Address:", winner);
    console.log("Winning Entry:", winningEntry.toString());
    console.log("Status: Waiting for reward dispersal...");

    return { winner, winningEntry, needsAction: true };
  }
}
```

#### 3. Trigger Manual Dispersal

```javascript
async function disperseRewards(raffleAddress, signer) {
  const factory = new ethers.Contract(FACTORY_ADDRESS, FACTORY_ABI, signer);

  try {
    // Check if ready
    const raffle = new ethers.Contract(raffleAddress, RAFFL_ABI, provider);
    if (!(await raffle.shouldDisperseRewards())) {
      throw new Error("Raffle not ready for dispersal");
    }

    // Disperse
    const tx = await factory.disperseRewards(raffleAddress, {
      gasLimit: 500000, // Safety buffer
    });

    const receipt = await tx.wait();

    console.log("Rewards dispersed!");
    console.log("Transaction:", receipt.transactionHash);

    return { success: true, txHash: receipt.transactionHash };
  } catch (error) {
    console.error("Dispersal failed:", error);
    return { success: false, error: error.message };
  }
}
```

#### 4. Monitor Complete Flow

```javascript
async function monitorRaffleProgress(raffleAddress) {
  const raffle = new ethers.Contract(raffleAddress, RAFFL_ABI, provider);
  const factory = new ethers.Contract(FACTORY_ADDRESS, FACTORY_ABI, provider);

  // Listen for WinnerDrawn event
  raffle.on("WinnerDrawn", (requestId, winnerEntry, winner, totalEntries) => {
    console.log("🎉 Winner Drawn!");
    console.log("Winner:", winner);
    console.log("Entry:", winnerEntry.toString());

    // Show "Disperse Rewards" button in UI
    displayDisperseButton(raffleAddress);
  });

  // Listen for RewardsDispersed event
  raffle.on("RewardsDispersed", (winner) => {
    console.log("💰 Rewards Dispersed!");
    console.log("Winner:", winner);

    // Update UI to show completion
    displayCompletionMessage(raffleAddress, winner);
  });
}
```

#### 5. UI State Management

```javascript
function getRaffleUIState(gameStatus, shouldDisperse, winner) {
  const states = {
    0: {
      // Initialized
      title: "Active",
      description: "Raffle is accepting entries",
      action: "Buy Entries",
      color: "green",
    },
    1: {
      // FailedDraw
      title: "Failed",
      description: "Minimum entries not met",
      action: "Request Refund",
      color: "red",
    },
    2: {
      // DrawStarted
      title: "Drawing Winner",
      description: "Waiting for random number...",
      action: null,
      color: "yellow",
    },
    3: {
      // WinnerDrawn
      title: "Winner Selected!",
      description: `Winner: ${winner}`,
      action: "Disperse Rewards",
      color: "blue",
      showWinner: true,
    },
    4: {
      // SuccessDraw
      title: "Complete",
      description: "Raffle finished successfully",
      action: null,
      color: "green",
    },
  };

  return states[gameStatus];
}
```

### For Backend Developers (Keeper/Bot)

#### Comprehensive Monitoring Bot

```javascript
class RaffleKeeperBot {
  constructor(provider, signer, factoryAddress) {
    this.provider = provider;
    this.factory = new ethers.Contract(factoryAddress, FACTORY_ABI, signer);
    this.retryThreshold = 3600; // 1 hour
    this.dispersalCheckInterval = 300; // 5 minutes
  }

  async monitorActiveRaffles() {
    const activeRaffles = await this.factory.activeRaffles();

    for (const { raffle: raffleAddress } of activeRaffles) {
      await this.processRaffle(raffleAddress);
    }
  }

  async processRaffle(raffleAddress) {
    const raffle = new ethers.Contract(raffleAddress, RAFFL_ABI, this.provider);

    // Priority 1: Check if needs reward dispersal
    if (await raffle.shouldDisperseRewards()) {
      await this.disperseRewards(raffleAddress);
      return;
    }

    // Priority 2: Check VRF status
    const [requestId, requestTime, status] = await this.factory.getVRFRequestInfo(raffleAddress);

    if (status === 1) {
      // Pending
      const elapsed = Date.now() / 1000 - requestTime.toNumber();

      // Emergency fail if > 24h
      if (elapsed > 86400) {
        await this.emergencyFail(raffleAddress);
      }
      // Retry if > 1h
      else if (elapsed > this.retryThreshold) {
        await this.retryVRF(raffleAddress);
      }
    }
  }

  async disperseRewards(raffleAddress) {
    console.log(`Dispersing rewards for ${raffleAddress}`);
    try {
      const tx = await this.factory.disperseRewards(raffleAddress, {
        gasLimit: 500000,
      });
      await tx.wait();
      console.log(`✓ Rewards dispersed: ${raffleAddress}`);
    } catch (error) {
      console.error(`✗ Dispersal failed: ${error.message}`);
    }
  }

  async retryVRF(raffleAddress) {
    console.log(`Retrying VRF for ${raffleAddress}`);
    try {
      const tx = await this.factory.retryVRFRequest(raffleAddress, {
        gasLimit: 200000,
      });
      await tx.wait();
      console.log(`✓ VRF retry successful: ${raffleAddress}`);
    } catch (error) {
      console.error(`✗ VRF retry failed: ${error.message}`);
    }
  }

  async emergencyFail(raffleAddress) {
    console.log(`Emergency failing ${raffleAddress}`);
    try {
      const tx = await this.factory.emergencyFailRaffle(raffleAddress, {
        gasLimit: 150000,
      });
      await tx.wait();
      console.log(`✓ Emergency failed: ${raffleAddress}`);
    } catch (error) {
      console.error(`✗ Emergency fail failed: ${error.message}`);
    }
  }

  async start(intervalMs = 300000) {
    console.log("🤖 Raffle Keeper Bot started");
    console.log(`Monitoring every ${intervalMs / 1000}s`);

    while (true) {
      try {
        await this.monitorActiveRaffles();
      } catch (error) {
        console.error("Monitoring error:", error);
      }

      await new Promise((resolve) => setTimeout(resolve, intervalMs));
    }
  }
}

// Usage
const bot = new RaffleKeeperBot(provider, signer, FACTORY_ADDRESS);
bot.start();
```

---

## Monitoring & Automation

### Critical Events to Monitor

#### 1. WinnerDrawn Event

```solidity
event WinnerDrawn(
    uint256 indexed requestId,
    uint256 winnerEntry,
    address user,
    uint256 entries
);
```

**Action**: Trigger reward dispersal (automated or manual)

#### 2. RewardsDispersed Event

```solidity
event RewardsDispersed(address indexed winner);
```

**Action**: Update UI, mark raffle complete

#### 3. VRFRequestRetried Event

```solidity
event VRFRequestRetried(
    address indexed raffle,
    uint256 indexed requestId
);
```

**Action**: Log retry, monitor new request

#### 4. RaffleEmergencyFailed Event

```solidity
event RaffleEmergencyFailed(address indexed raffle);
```

**Action**: Alert team, enable refunds

### Monitoring Strategy

```javascript
async function setupMonitoring() {
  const factory = new ethers.Contract(FACTORY_ADDRESS, FACTORY_ABI, provider);

  // Monitor winner selection
  factory.on("RandomWordsFulfilled", async (requestId) => {
    const raffle = await factory._requestIds(requestId);
    console.log(`Winner selected for raffle: ${raffle}`);

    // Trigger dispersal after delay
    setTimeout(async () => {
      const contract = new ethers.Contract(raffle, RAFFL_ABI, provider);
      if (await contract.shouldDisperseRewards()) {
        await factory.disperseRewards(raffle);
      }
    }, 60000); // 1 minute delay
  });

  // Monitor dispersals
  const raffleInterface = new ethers.utils.Interface(RAFFL_ABI);
  provider.on(
    {
      topics: [raffleInterface.getEventTopic("RewardsDispersed")],
    },
    (log) => {
      const parsed = raffleInterface.parseLog(log);
      console.log(`Rewards dispersed to: ${parsed.args.winner}`);
    },
  );
}
```

---

## Security Considerations

### Two-Step Process Security

✅ **Benefits**:

- VRF callback cannot fail due to gas limits
- Winner selection is atomic and guaranteed
- Reward dispersal can be retried infinitely
- No single point of failure

⚠️ **Considerations**:

- Winner is public before rewards dispersed (expected behavior)
- Small time gap between winner selection and dispersal (acceptable)
- Anyone can trigger dispersal (intentional, beneficial)

### Gas Safety

**VRF Callback (setWinner)**:

- Only stores 3 state variables
- No external calls
- No loops
- Gas usage: ~50-80k (well within limits)

**Reward Dispersal**:

- No gas limits
- Can handle complex transfers
- Protected by reentrancy guard
- Can be retried if fails

### Economic Security

✅ **Protected**:

- Winner deterministically calculated
- No manipulation possible
- Prizes locked until dispersal
- Pool protected until dispersal

### Access Control

```solidity
// Only factory can set winner
function setWinner(...) external onlyFactory

// Anyone can disperse (after winner set)
function disperseRewards() external nonReentrant

// Anyone can retry/emergency fail
function retryVRFRequest(address raffle) external
function emergencyFailRaffle(address raffle) external
```

---

## Appendix

### Gas Costs

| Operation             | Gas       | Notes             |
| --------------------- | --------- | ----------------- |
| `setWinner`           | ~50-80k   | VRF callback      |
| `disperseRewards`     | ~300-500k | Depends on prizes |
| `retryVRFRequest`     | ~150k     | New VRF request   |
| `emergencyFailRaffle` | ~120k     | State update      |
| View functions        | ~3-5k     | Free (no tx)      |

### Complete Flow Example

```javascript
// 1. Raffle ends, automation triggers draw
await factory.performUpkeep(performData);
// State: DrawStarted

// 2. VRF fulfills, winner selected
// VRF Coordinator calls fulfillRandomWords
// State: WinnerDrawn

// 3. Winner is now known
const winner = await raffle.winner();
console.log("Winner:", winner);

// 4. Trigger dispersal (any of these work):
// Option A: Automation
await factory.performUpkeep(performData);
// Option B: Manual
await factory.disperseRewards(raffleAddress);
// Option C: Direct
await raffle.disperseRewards();

// State: SuccessDraw
// Winner has prizes and pool funds
```

---

## Version History

- **v2.1.0** (Current): Two-step VRF process
- **v2.0.0**: VRF retry and emergency fail
- **v1.0.0**: Initial release

---

## Support

- **GitHub**: [Protocol Repository](https://github.com/Raffl-Protocol/protocol)
- **Discord**: [Developer Support](https://discord.gg/raffl)
- **Docs**: [Full Documentation](https://docs.raffl.io)

---

_Last Updated: January 2026_ _Solidity Version: 0.8.33_ _Protocol Version: 2.1.0_
