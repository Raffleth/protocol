# Raffl Protocol - Complete Documentation

## Overview

**Raffl Protocol** is a decentralized raffle/lottery platform built on Ethereum. It enables users to create and
participate in provably fair raffles with customizable prizes (ERC-20 tokens, ERC-721 NFTs) using Chainlink VRF for
verifiable randomness and Chainlink Automation for lifecycle management.

---

## Architecture

```
                                    RAFFL PROTOCOL ARCHITECTURE

    +-----------------------------------------------------------------------------------+
    |                              EXTERNAL ACTORS                                       |
    +-----------------------------------------------------------------------------------+
    |                                                                                    |
    |   +----------+    +-------------------+    +---------------+    +---------------+  |
    |   |  Users   |    | Chainlink         |    | Chainlink VRF |    | Fee Collector |  |
    |   |          |    | Automation        |    |               |    |               |  |
    |   +----+-----+    +--------+----------+    +-------+-------+    +-------+-------+  |
    |        |                   |                      |                     |          |
    +--------|-------------------|----------------------|---------------------|----------+
             |                   |                      |                     |
             | createRaffle()    | checkUpkeep()        | fulfillRandom       | setFee()
             | buyEntries()      | performUpkeep()      | Words()             |
             | refund*()         |                      |                     |
             | disperseRewards() |                      |                     |
             v                   v                      v                     v
    +-----------------------------------------------------------------------------------+
    |                              RAFFLE FACTORY                                        |
    |                                                                                    |
    |   Inherits:                                                                        |
    |   - VRFConsumerBaseV2Plus (Chainlink VRF V2.5)                                     |
    |   - AutomationCompatibleInterface (Chainlink Automation)                           |
    |   - FactoryFeeManager (Fee management with time-delayed changes)                   |
    |                                                                                    |
    |   Key State:                                                                       |
    |   - implementation (Raffl master copy)                                             |
    |   - _raffles (mapping: address => bool)                                            |
    |   - _activeRaffles (array of ActiveRaffle structs)                                 |
    |   - _requestIds (mapping: VRF requestId => raffle address)                         |
    |   - _raffleVRFRequests (mapping: raffle => VRFRequest)                             |
    |                                                                                    |
    +----------------------------------+------------------------------------------------+
                                       |
                        initialize()   | setSuccessCriteria()
                        (CREATE2)      | setFailedCriteria()
                                       | setWinner()
                                       v
    +-----------------------------------------------------------------------------------+
    |                              RAFFL (Clone Instance)                                |
    |                                                                                    |
    |   Inherits:                                                                        |
    |   - ReentrancyGuardUpgradeable (Security)                                          |
    |   - EntriesManager (ERC721A-inspired entry tracking)                               |
    |   - IRaffl (Interface)                                                             |
    |                                                                                    |
    |   Key State:                                                                       |
    |   - factory, creator, manager addresses                                            |
    |   - prizes[], tokenGates[], extraRecipient                                         |
    |   - deadline, minEntries, entryPrice, entryToken                                   |
    |   - pool, settled, prizesRefunded flags                                            |
    |   - gameStatus, winningEntry, winner, requestId                                    |
    |                                                                                    |
    +----------------------------------+------------------------------------------------+
                                       |
                                       | Token operations
                                       v
    +-----------------------------------------------------------------------------------+
    |                              TOKEN LIB                                             |
    |                                                                                    |
    |   - balanceOf(token, account)                                                      |
    |   - safeTransfer(token, to, amount)                                                |
    |   - safeTransferFrom(token, from, to, amount)                                      |
    |                                                                                    |
    +-----------------------------------------------------------------------------------+
```

---

## Complete Lifecycle Flowchart

```
                           RAFFL PROTOCOL - COMPLETE LIFECYCLE FLOWCHART

    +===================================================================================+
    |                           PHASE 1: RAFFLE CREATION                                |
    +===================================================================================+

                                        START
                                          |
                                          v
                            +---------------------------+
                            |   User prepares prizes    |
                            |   (ERC20/ERC721 tokens)   |
                            +-------------+-------------+
                                          |
                                          v
                            +---------------------------+
                            |  Approve prizes to        |
                            |  RafflFactory address     |
                            +-------------+-------------+
                                          |
                                          v
                            +---------------------------+
                            |  Call createRaffle()      |
                            |  with parameters:         |
                            |  - entryToken             |
                            |  - entryPrice             |
                            |  - minEntries             |
                            |  - deadline               |
                            |  - prizes[]               |
                            |  - tokenGates[]           |
                            |  - extraRecipient         |
                            +-------------+-------------+
                                          |
                                          v
                   +----------------------+----------------------+
                   |        FACTORY: createRaffle()              |
                   +---------------------------------------------+
                   |  1. Validate deadline > block.timestamp     |
                   |  2. Validate prizes.length > 0              |
                   |  3. Deploy Raffl clone via CREATE2          |
                   |  4. Process creation fee (if any)           |
                   |  5. Call raffl.initialize()                 |
                   |  6. Transfer prizes to raffle contract      |
                   |  7. Add to _raffles mapping                 |
                   |  8. Add to _activeRaffles array             |
                   |  9. Emit RaffleCreated event                |
                   +----------------------+----------------------+
                                          |
                                          v
                            +---------------------------+
                            |  GameStatus.Initialized   |
                            |  (Raffle is now ACTIVE)   |
                            +---------------------------+


    +===================================================================================+
    |                         PHASE 2: ENTRY ACQUISITION                                |
    +===================================================================================+

                            +---------------------------+
                            |  GameStatus.Initialized   |
                            +-------------+-------------+
                                          |
                                          v
                            +---------------------------+
                            |  User calls buyEntries()  |
                            |  with quantity            |
                            +-------------+-------------+
                                          |
                                          v
                                 +--------+--------+
                                 | entryPrice > 0? |
                                 +--------+--------+
                                  |               |
                              YES |               | NO (Free Raffle)
                                  v               v
                 +----------------+---+   +---+----------------+
                 |   PAID ENTRIES     |   |   FREE ENTRIES     |
                 +--------------------+   +--------------------+
                 | 1. Check deadline  |   | 1. Check deadline  |
                 | 2. Check max limit |   | 2. Check tokenGates|
                 | 3. Check tokenGates|   | 3. Check user has  |
                 | 4. Calculate value |   |    no entries yet  |
                 | 5. Transfer payment|   | 4. Mint 1 entry    |
                 | 6. Add to pool     |   | 5. Emit event      |
                 | 7. Mint entries    |   +--------------------+
                 | 8. Emit event      |
                 +--------+-----------+
                          |
                          v
                 +--------+--------+
                 |  Entries minted  |
                 |  to user account |
                 +-----------------+

                          |
            (Repeat until deadline)
                          |
                          v

    +===================================================================================+
    |                       PHASE 3: DEADLINE PROCESSING                                |
    +===================================================================================+

                            +---------------------------+
                            |   Deadline Reached        |
                            |   block.timestamp >=      |
                            |   raffle.deadline         |
                            +-------------+-------------+
                                          |
                                          v
                   +----------------------+----------------------+
                   |     Chainlink Automation: checkUpkeep()     |
                   +---------------------------------------------+
                   |  Loop through _activeRaffles:               |
                   |  - Check if deadline passed                 |
                   |  - Check if upkeep not performed            |
                   |  - Check if needs dispersal                 |
                   +----------------------+----------------------+
                                          |
                                          v
                            +-------------+-------------+
                            | upkeepNeeded = true       |
                            | Return raffle info        |
                            +-------------+-------------+
                                          |
                                          v
                   +----------------------+----------------------+
                   |     Chainlink Automation: performUpkeep()   |
                   +----------------------+----------------------+
                                          |
                                          v
                                 +--------+--------+
                                 | criteriaMet?    |
                                 | (entries >=     |
                                 |  minEntries)    |
                                 +--------+--------+
                                  |               |
                              YES |               | NO
                                  v               v
            +---------------------+---+   +---+---------------------+
            |    SUCCESS PATH         |   |    FAILURE PATH         |
            +-------------------------+   +-------------------------+
            | 1. Request VRF random   |   | 1. setFailedCriteria()  |
            |    words from Chainlink |   | 2. Set GameStatus to    |
            | 2. Store VRFRequest     |   |    FailedDraw           |
            |    with Pending status  |   | 3. Remove from          |
            | 3. setSuccessCriteria() |   |    _activeRaffles       |
            | 4. Set GameStatus to    |   | 4. Emit event           |
            |    DrawStarted          |   +------------+------------+
            | 5. Emit event           |                |
            +------------+------------+                v
                         |              +-------------------------+
                         |              | SKIP TO PHASE 5B:       |
                         |              | FAILED DRAW HANDLING    |
                         v              +-------------------------+

    +===================================================================================+
    |                        PHASE 4: WINNER SELECTION                                  |
    +===================================================================================+

                            +---------------------------+
                            |  GameStatus.DrawStarted   |
                            |  VRF Request Pending      |
                            +-------------+-------------+
                                          |
                                          v
                   +----------------------+----------------------+
                   |  Chainlink VRF Coordinator responds        |
                   |  Calls: fulfillRandomWords(requestId,      |
                   |                            randomWords[])  |
                   +----------------------+----------------------+
                                          |
                                          v
                   +----------------------+----------------------+
                   |  FACTORY: fulfillRandomWords()              |
                   +---------------------------------------------+
                   |  1. Get raffle from _requestIds[requestId] |
                   |  2. Update VRFRequest status to Fulfilled  |
                   |  3. Call raffl.setWinner(requestId,        |
                   |                          randomWords[0])   |
                   +----------------------+----------------------+
                                          |
                                          v
                   +----------------------+----------------------+
                   |  RAFFL: setWinner()                         |
                   +---------------------------------------------+
                   |  1. winningEntry = randomNumber %          |
                   |                    totalEntries()          |
                   |  2. winner = ownerOf(winningEntry)         |
                   |  3. Store requestId, winningEntry, winner  |
                   |  4. Update gameStatus to WinnerDrawn       |
                   |  5. Emit WinnerDrawn event                 |
                   +----------------------+----------------------+
                                          |
                                          v
                            +---------------------------+
                            |  GameStatus.WinnerDrawn   |
                            |  Ready for dispersal      |
                            +---------------------------+


    +===================================================================================+
    |                       PHASE 5A: REWARD DISPERSAL                                  |
    +===================================================================================+

                            +---------------------------+
                            |  GameStatus.WinnerDrawn   |
                            +-------------+-------------+
                                          |
                      +-------------------+-------------------+
                      |                   |                   |
                      v                   v                   v
            +---------+--------+ +--------+--------+ +--------+---------+
            | Chainlink Auto   | | Factory call    | | Direct call      |
            | performUpkeep()  | | disperseRewards | | raffl.disperse   |
            | detects ready    | | (raffle)        | | Rewards()        |
            +---------+--------+ +--------+--------+ +--------+---------+
                      |                   |                   |
                      +-------------------+-------------------+
                                          |
                                          v
                   +----------------------+----------------------+
                   |  RAFFL: disperseRewards()                   |
                   +---------------------------------------------+
                   |  1. Validate gameStatus == WinnerDrawn     |
                   |  2. _transferPrizes():                     |
                   |     - Transfer all prizes to winner        |
                   |  3. _transferPool():                       |
                   |     a. Calculate poolFee amount            |
                   |     b. Calculate extraRecipient share      |
                   |     c. Transfer fee to feeCollector        |
                   |     d. Transfer share to extraRecipient    |
                   |     e. Transfer remainder to creator       |
                   |  4. Update gameStatus to SuccessDraw       |
                   |  5. Emit RewardsDispersed event            |
                   +----------------------+----------------------+
                                          |
                                          v
                   +----------------------+----------------------+
                   |  Factory removes from _activeRaffles        |
                   +----------------------+----------------------+
                                          |
                                          v
                            +---------------------------+
                            |  GameStatus.SuccessDraw   |
                            |  RAFFLE COMPLETE          |
                            +---------------------------+


    +===================================================================================+
    |                       PHASE 5B: FAILED DRAW HANDLING                              |
    +===================================================================================+

                            +---------------------------+
                            |  GameStatus.FailedDraw    |
                            +-------------+-------------+
                                          |
                     +--------------------+--------------------+
                     |                                         |
                     v                                         v
        +------------+-------------+             +-------------+------------+
        |  ENTRY HOLDERS           |             |  RAFFLE CREATOR          |
        |  Call refundEntries()    |             |  Call refundPrizes()     |
        +------------+-------------+             +-------------+------------+
                     |                                         |
                     v                                         v
        +------------+-------------+             +-------------+------------+
        | 1. Validate FailedDraw   |             | 1. Validate FailedDraw   |
        | 2. Validate user entries |             | 2. Validate caller =     |
        | 3. Validate entryPrice>0 |             |    creator               |
        | 4. Mark user refunded    |             | 3. Validate prizes not   |
        | 5. Calculate refund      |             |    already refunded      |
        | 6. Transfer payment back |             | 4. Transfer all prizes   |
        | 7. Emit EntriesRefunded  |             |    back to creator       |
        +--------------------------+             | 5. Emit PrizesRefunded   |
                                                 +--------------------------+


    +===================================================================================+
    |                         VRF RECOVERY MECHANISMS                                   |
    +===================================================================================+

                            +---------------------------+
                            |  GameStatus.DrawStarted   |
                            |  VRF Request Pending      |
                            +-------------+-------------+
                                          |
                                          v
                                 +--------+--------+
                                 | VRF Response    |
                                 | received?       |
                                 +--------+--------+
                                  |               |
                              YES |               | NO (Timeout)
                                  |               |
                                  v               v
                     +------------+    +---------+---------+
                     | Continue to|    | After 24 hours:   |
                     | Phase 4    |    | Has timed out?    |
                     +------------+    +---------+---------+
                                                 |
                              +------------------+------------------+
                              |                                     |
                              v                                     v
               +--------------+--------------+       +--------------+--------------+
               | retryVRFRequest(raffle)     |       | emergencyFailRaffle(raffle) |
               +-----------------------------+       +-----------------------------+
               | Anyone can call             |       | Anyone can call after 24h   |
               | 1. Validate pending status  |       | 1. Validate timed out       |
               | 2. Cancel old request       |       | 2. Set VRF status to Failed |
               | 3. Request new VRF          |       | 3. Call setFailedCriteria() |
               | 4. Update request tracking  |       | 4. Remove from active       |
               | 5. Emit VRFRequestRetried   |       | 5. Emit EmergencyFailed     |
               +-----------------------------+       +-----------------------------+
```

---

## Data Structures

### Enums

```solidity
// Prize asset types
enum AssetType {
    ERC20,   // Fungible token prize
    ERC721   // Non-fungible token prize
}

// Raffle game states
enum GameStatus {
    Initialized,   // 0: Accepting entries
    FailedDraw,    // 1: Minimum entries not met
    DrawStarted,   // 2: VRF requested
    WinnerDrawn,   // 3: Winner selected
    SuccessDraw    // 4: Rewards dispersed
}

// VRF request states
enum VRFStatus {
    None,      // No request made
    Pending,   // Awaiting response
    Fulfilled, // Successfully completed
    Failed     // Timed out or failed
}
```

### Core Structs

```solidity
// Prize definition
struct Prize {
    address asset;        // Token contract address
    AssetType assetType;  // ERC20 or ERC721
    uint256 value;        // Amount (ERC20) or tokenId (ERC721)
}

// Entry restriction
struct TokenGate {
    address token;   // Token contract to check
    uint256 amount;  // Minimum balance required
}

// Revenue sharing
struct ExtraRecipient {
    address recipient;       // Extra recipient address
    uint64 sharePercentage;  // Share percentage (1 ether = 100%)
}

// Fee configuration
struct FeeData {
    address feeCollector;      // Fee recipient address
    uint64 creationFee;        // Fixed creation fee
    uint64 poolFeePercentage;  // Pool percentage fee
}

// VRF request tracking
struct VRFRequest {
    uint256 requestId;    // Chainlink VRF request ID
    uint256 requestTime;  // Timestamp of request
    VRFStatus status;     // Current status
}

// Active raffle tracking
struct ActiveRaffle {
    address raffle;    // Raffle contract address
    uint256 deadline;  // Deadline timestamp
}
```

---

## State Transitions

```
                        GAME STATUS STATE MACHINE

    +---------------+                              +---------------+
    |               |                              |               |
    | Initialized   |---(deadline + criteria)----->| DrawStarted   |
    |               |                              |               |
    +-------+-------+                              +-------+-------+
            |                                              |
            |                                              |
            | (deadline + !criteria)                       | (VRF fulfilled)
            |                                              |
            v                                              v
    +---------------+                              +---------------+
    |               |                              |               |
    | FailedDraw    |                              | WinnerDrawn   |
    |               |                              |               |
    +---------------+                              +-------+-------+
                                                           |
                                                           |
                                                           | (disperseRewards)
                                                           |
                                                           v
                                                   +---------------+
                                                   |               |
                                                   | SuccessDraw   |
                                                   |               |
                                                   +---------------+


                        VRF STATUS STATE MACHINE

    +---------------+                              +---------------+
    |               |                              |               |
    |    None       |-----(request VRF)----------->|   Pending     |
    |               |                              |               |
    +---------------+                              +-------+-------+
                                                     |         |
                                    (fulfillRandom)  |         | (24h timeout)
                                                     |         |
                                                     v         v
                                           +---------+    +----+------+
                                           |Fulfilled|    |  Failed   |
                                           +---------+    +-----------+
```

---

## Fee System

### Fee Structure

```
                            POOL DISTRIBUTION ON SUCCESS

    +---------------------------+
    |      TOTAL POOL           |
    |    (All entry payments)   |
    +-------------+-------------+
                  |
                  v
    +-------------+-------------+
    |     Pool Fee (0-10%)      |-----> Fee Collector
    +-------------+-------------+
                  |
                  v
    +-------------+-------------+
    |   Extra Recipient Share   |-----> Extra Recipient (optional)
    |    (configurable %)       |
    +-------------+-------------+
                  |
                  v
    +-------------+-------------+
    |      Remainder            |-----> Raffle Creator
    +---------------------------+
```

### Fee Change Timeline

```
    scheduleGlobalPoolFee(5%)
              |
              v
    +---------+---------+
    | Upcoming fee set  |
    | nextValue = 5%    |
    | valueChangeAt =   |
    | now + 1 hour      |
    +---------+---------+
              |
              | (1 hour delay)
              v
    +---------+---------+
    | Fee now active    |
    | Current value = 5%|
    +-------------------+
```

---

## Entry System (EntriesManager)

Inspired by ERC721A for gas-efficient batch minting:

```solidity
// Efficient storage using ownership boundaries
mapping(uint256 => address) private _ownerships;  // entryId => owner (sparse)
mapping(address => uint256) private _balances;    // user => entry count

// Only stores ownership at minting boundaries
// Example: User A mints entries 0-99, User B mints 100-149
// _ownerships[0] = User A    (boundary)
// _ownerships[100] = User B  (boundary)
// Entries 1-99 inherit ownership from entry 0
```

---

## External Dependencies

### Chainlink Integration

| Service        | Purpose                                 | Contract                      |
| -------------- | --------------------------------------- | ----------------------------- |
| **VRF V2.5**   | Verifiable random number generation     | VRFConsumerBaseV2Plus         |
| **Automation** | Automated deadline handling & dispersal | AutomationCompatibleInterface |

### OpenZeppelin

| Contract                   | Purpose                      |
| -------------------------- | ---------------------------- |
| ReentrancyGuardUpgradeable | Reentrancy attack protection |
| Initializable              | Proxy initialization pattern |

---

## Chainlink Exception Handling

The protocol uses a **two-step process** that separates VRF callback from reward distribution, providing robust
exception handling for Chainlink interactions.

### Architecture: Two-Step Winner Selection

```
STEP 1: VRF Request (performUpkeep)
    │
    └──► requestRandomWords() ──► Chainlink VRF Coordinator
                                          │
                                          ▼
STEP 2: VRF Callback (fulfillRandomWords) - MINIMAL WORK
    │   • Only updates storage variables (~50k gas)
    │   • NO external calls (no transfers)
    │   • NO loops over prizes/entries
    │   • Cannot fail due to gas limits
    │
    └──► setWinner() stores: requestId, winningEntry, winner, gameStatus
                                          │
                                          ▼
STEP 3: Dispersal (separate transaction) - HEAVY WORK
        • Transfers all prizes to winner
        • Distributes pool (fees, creator, extra recipient)
        • Can be triggered by ANYONE (permissionless)
        • Can be RETRIED if it fails
        • Protected by nonReentrant modifier
```

### Why This Design?

| Problem                             | Solution                         |
| ----------------------------------- | -------------------------------- |
| VRF callback gas limit (~500k)      | `setWinner()` uses < 50k gas     |
| Prize transfer failures in callback | Transfers happen in separate tx  |
| Stuck/failed VRF                    | Retry mechanism + emergency fail |
| Single point of failure             | Permissionless dispersal         |

### Exception Scenarios and Handling

#### 1. VRF Callback Out of Gas

**Risk**: Chainlink VRF has a `callbackGasLimit` (~500k default). Complex operations could exceed this.

**Protection**: `setWinner()` only performs storage writes:

```solidity
function setWinner(uint256 _requestId, uint256 randomNumber) external onlyFactory {
    // Only storage operations - guaranteed to succeed
    uint256 _winningEntry = randomNumber % totalEntries();
    address _winner = ownerOf(_winningEntry);

    requestId = _requestId;
    winningEntry = _winningEntry;
    winner = _winner;
    gameStatus = GameStatus.WinnerDrawn;
}
```

#### 2. VRF Never Responds

**Risk**: Network congestion, Chainlink issues, or insufficient LINK could prevent response.

**Protection**: Retry mechanism available immediately:

```solidity
// Anyone can call to request new random words
function retryVRFRequest(address raffle) external;
```

**Recovery Flow**:

```
DrawStarted ──► [VRF stuck] ──► retryVRFRequest() ──► [New VRF] ──► WinnerDrawn
```

#### 3. VRF Stuck > 24 Hours

**Risk**: Prolonged VRF failure leaves raffle in limbo.

**Protection**: Emergency fail mechanism after timeout:

```solidity
// Anyone can call after 24 hours
function emergencyFailRaffle(address raffle) external;
```

**Recovery Flow**:

```
DrawStarted ──► [24h timeout] ──► emergencyFailRaffle() ──► FailedDraw ──► Refunds
```

#### 4. Stale VRF Response After Retry

**Risk**: Old VRF request responds after a retry was issued.

**Protection**: State check in `setWinner()`:

```solidity
if (gameStatus != GameStatus.DrawStarted) revert Errors.DrawNotStarted();
```

**Scenario**:

```
1. VRF Request #1 sent
2. No response, retry called
3. VRF Request #2 sent
4. Request #2 fulfilled → Winner set, status = WinnerDrawn
5. Request #1 finally responds → REVERTS (status != DrawStarted)
```

#### 5. Prize/Pool Transfer Failures

**Risk**: ERC20/ERC721 transfers could fail during dispersal.

**Protection**: Dispersal is a separate, retryable transaction:

```solidity
// Anyone can call, can be retried
function disperseRewards(address raffle) external;
```

**Note**: If a malicious/broken token prevents dispersal, the raffle will be stuck in `WinnerDrawn` state. The winner is
known but cannot receive prizes. This is a limitation when dealing with non-standard tokens.

#### 6. Subscription Runs Out of LINK

**Risk**: VRF request fails if subscription has insufficient LINK.

**Protection**:

- VRF request reverts, raffle stays in `Initialized` state
- Upkeep will retry after subscription is funded
- Or criteria will fail naturally at deadline

### VRF Request Tracking

```solidity
struct VRFRequest {
    uint256 requestId;    // Current request ID
    uint256 requestTime;  // When request was made
    VRFStatus status;     // None, Pending, Fulfilled, Failed
}

// Mappings
_requestIds[requestId] => raffle address
_raffleVRFRequests[raffle] => VRFRequest
```

### Recovery Function Reference

| Function                      | Who Can Call | When Available       | Effect                |
| ----------------------------- | ------------ | -------------------- | --------------------- |
| `retryVRFRequest(raffle)`     | Anyone       | Status = Pending     | New VRF request       |
| `emergencyFailRaffle(raffle)` | Anyone       | After 24h timeout    | Sets FailedDraw       |
| `disperseRewards(raffle)`     | Anyone       | Status = WinnerDrawn | Transfers prizes/pool |

### Gas Usage

| Operation               | Typical Gas        | VRF Callback Safe? |
| ----------------------- | ------------------ | ------------------ |
| `setWinner()`           | ~50,000            | Yes                |
| `disperseRewards()`     | 100,000 - 500,000+ | N/A (separate tx)  |
| `retryVRFRequest()`     | ~100,000           | N/A                |
| `emergencyFailRaffle()` | ~50,000            | N/A                |

---

## Security Features

1. **ReentrancyGuard**: All external calls protected
2. **Access Control**: Role-based function restrictions
3. **Time-Delayed Fees**: 1-hour delay on fee changes
4. **Input Validation**: Comprehensive parameter checks
5. **Safe Transfers**: TokenLib with return value verification
6. **VRF Recovery**: 24-hour timeout with retry/emergency fail options

---

## Supported Networks

| Network          | VRF Coordinator                              | Status       |
| ---------------- | -------------------------------------------- | ------------ |
| Ethereum Mainnet | -                                            | Configurable |
| Ethereum Sepolia | `0x9DdfaCa8183c41ad55329BdeeD9F6A8d53168B1B` | Configured   |
| Polygon          | `0xec0Ed46f36576541C75739E915ADbCb3DE24bD77` | Configured   |
| Polygon Amoy     | `0x343300b5d84D444B2ADc9116FEF1bED02BE49Cf2` | Configured   |
| Arbitrum         | `0x3C0Ca683b403E37668AE3DC4FB62F4B29B6f7a3e` | Configured   |
| Base             | `0xd5D517aBE5cF79B7e95eC98dB0f0277788aFF634` | Configured   |

---

## Key Constants

### Protocol Constants (from source code)

| Constant               | Location                 | Value             | Description                                       |
| ---------------------- | ------------------------ | ----------------- | ------------------------------------------------- |
| `MAX_POOL_FEE`         | FactoryFeeManager.sol:19 | `0.1 ether` (10%) | Maximum pool fee percentage                       |
| `VRF_REQUEST_TIMEOUT`  | RafflFactory.sol:90      | `24 hours`        | Time before VRF can be retried/failed             |
| `MAX_ENTRIES_PER_USER` | Raffl.sol:71             | `2^64 - 1`        | Max entries per user (paid raffles)               |
| `MAX_TOTAL_ENTRIES`    | Raffl.sol:73             | `2^256 - 1`       | Max total entries per raffle                      |
| `ONE`                  | Raffl.sol:75             | `1 ether`         | 100% representation for percentages               |
| Fee Change Delay       | FactoryFeeManager.sol    | `1 hours`         | Time before scheduled fees take effect            |
| Min Pool Fee           | FactoryFeeManager.sol:63 | `0`               | Minimum pool fee (returned by `minPoolFee()`)     |
| Free Entry Max         | Raffl.sol:369            | `1`               | Max entries per user for free raffles (hardcoded) |

### EntriesManager Internal Constants

| Constant                      | Value            | Description                   |
| ----------------------------- | ---------------- | ----------------------------- |
| `_BITMASK_ADDRESS_DATA_ENTRY` | `(1 << 64) - 1`  | Mask for entry data           |
| `_BITPOS_NUMBER_MINTED`       | `64`             | Bit position for minted count |
| `_BITMASK_ADDRESS`            | `(1 << 160) - 1` | Mask for address extraction   |

### Test Default Values (Common.sol)

| Variable            | Value             | Description                  |
| ------------------- | ----------------- | ---------------------------- |
| `ENTRY_PRICE`       | `2 ether`         | Default entry price in tests |
| `MIN_ENTRIES`       | `10`              | Default minimum entries      |
| `DEADLINE_FROM_NOW` | `86400` (1 day)   | Default deadline offset      |
| `ERC20_AMOUNT`      | `50 ether`        | Default ERC20 prize amount   |
| `poolFeePercentage` | `0.05 ether` (5%) | Default pool fee in tests    |

---

## Token Gating System

Token gating allows raffle creators to restrict participation based on token holdings.

### Supported Token Standards

| Standard | Gate Behavior                                       |
| -------- | --------------------------------------------------- |
| ERC20    | User must hold `amount` or more tokens              |
| ERC721   | User must own `amount` or more NFTs from collection |

### Key Behaviors

```
GATE VALIDATION RULES:

1. Multiple Gates → All must pass (AND logic)
2. Check Timing   → Every buyEntries() call
3. Empty Gates[]  → Open raffle, anyone can participate
4. amount: 0      → No restriction (0 >= 0 passes)
```

### Edge Cases

- Token gate works with free entries (price=0)
- Users can lose eligibility mid-raffle if they transfer gate tokens
- Same token can appear multiple times; highest requirement applies

---

## Entry System Details

### Free Entries (Entry Price = 0)

| Rule               | Description                         |
| ------------------ | ----------------------------------- |
| Max Entries        | 1 entry per user (hard limit)       |
| Quantity Parameter | Ignored - always results in 1 entry |
| Pool Impact        | Pool remains at 0                   |
| Error on Re-entry  | `MaxUserEntriesReached`             |

### Paid Entries

| Rule                 | Description                               |
| -------------------- | ----------------------------------------- |
| Max Entries Per User | `2^64 - 1` (uint64 max)                   |
| Payment              | Must send exactly `entryPrice * quantity` |
| Min Entry Price      | 1 wei supported                           |
| Max Entry Price      | No limit (tested: 1000 ether)             |

### Deadline Boundaries

```
Time < deadline    → Entries ALLOWED
Time == deadline   → Entries CLOSED
Time > deadline    → Entries CLOSED

Error: EntriesPurchaseClosed
```

---

## VRF Edge Cases and Recovery

### Random Number Handling

| Input                             | Behavior                           |
| --------------------------------- | ---------------------------------- |
| Random = 0                        | Valid - selects entry 0            |
| Random = `type(uint256).max`      | Valid - modulo handles safely      |
| Random = multiple of totalEntries | Selects entry 0                    |
| Single entry raffle               | Any random → entry 0 (`x % 1 = 0`) |

### VRF Timeout and Recovery

```
RECOVERY OPTIONS (after 24 hours):

1. retryVRFRequest(raffle)      → Request new VRF, await response
2. emergencyFailRaffle(raffle)  → Force FailedDraw, enable refunds

Both are permissionless - anyone can trigger
```

---

## Fee System Architecture

### Fee Hierarchy

```
LOOKUP ORDER:
1. Custom fee for user (if enabled) → Use custom value
2. Global fee                       → Fallback
```

### Fee Types

| Type         | Description                | Timing             |
| ------------ | -------------------------- | ------------------ |
| Creation Fee | Fixed fee to create raffle | Raffle creation    |
| Pool Fee     | Percentage of entry pool   | On successful draw |

### Fee Scheduling (Time-Locked)

All fee changes require 1-hour delay:

- `scheduleGlobalPoolFee()`
- `scheduleGlobalCreationFee()`
- `scheduleCustomPoolFee()`
- `scheduleCustomCreationFee()`
- `toggleCustomPoolFee()`
- `toggleCustomCreationFee()`

---

## Extra Recipient Behavior

### Share Percentage

| Value           | Effect                             |
| --------------- | ---------------------------------- |
| 0 (0%)          | Extra recipient receives nothing   |
| 0.5 ether (50%) | Split 50/50 with creator           |
| 1 ether (100%)  | Extra recipient gets all           |
| > 1 ether       | `InvalidExtraRecipientShare` error |

### Distribution Formula

```solidity
afterFee = pool - poolFee
extraShare = (afterFee * sharePercentage) / 1 ether
creatorShare = afterFee - extraShare
```

### Special Cases

- `recipient = address(0)` → No extra recipient (creator gets all)
- Contract recipients must have `receive()` or `fallback()`

---

## Prize Requirements

### Initialization Requirements

| Requirement            | Error if Violated        |
| ---------------------- | ------------------------ |
| At least 1 prize       | `NoPrizesProvided`       |
| ERC20 prize amount > 0 | `ERC20PrizeAmountIsZero` |
| Deadline in future     | `DeadlineIsNotFuture`    |

### Prize Transfer Flow

```
CREATION:  Creator → Raffle Contract (via Factory)
SUCCESS:   Raffle Contract → Winner
FAILED:    Raffle Contract → Creator (via refundPrizes())
```

### Supported Configurations

- Multiple NFTs from same collection
- Multiple NFTs from different collections
- Mixed ERC20 + ERC721 prizes
- Large prize counts (20+ NFTs tested)
- Token ID = 0 supported for ERC721

---

## Refund Mechanisms

### Entry Refunds

| Condition                 | Required     |
| ------------------------- | ------------ |
| Game status               | `FailedDraw` |
| User has entries          | Yes          |
| User not already refunded | Yes          |

```solidity
// Anyone can trigger refunds for any user
function refundEntries(address user) external;
```

### Prize Refunds

- Only creator can call `refundPrizes()`
- Only available in `FailedDraw` state
- All prizes returned to creator

---

## Access Control

### Role-Based Permissions

| Role               | Capabilities                                            |
| ------------------ | ------------------------------------------------------- |
| **Owner**          | Transfer ownership, set fee collector, VRF subscription |
| **Fee Collector**  | Schedule/toggle all fee types                           |
| **Raffle Creator** | Refund prizes (on FailedDraw)                           |
| **Factory**        | Set winner, set success/failed criteria                 |

### Permissionless Operations

- `buyEntries()` - Anyone (subject to token gates)
- `refundEntries(user)` - Anyone can trigger
- `disperseRewards()` - Anyone can trigger
- `retryVRFRequest()` - Anyone can retry stuck VRF
- `emergencyFailRaffle()` - Anyone (after timeout)

### Ownership Transfer

Two-step process: `transferOwnership()` → `acceptOwnership()`

---

## Security Measures

### Reentrancy Protection

| Attack Vector          | Protection                           |
| ---------------------- | ------------------------------------ |
| Malicious ERC20 prize  | State updated before transfer        |
| Malicious ERC721 prize | State updated before transfer        |
| ETH receive callback   | State updated before transfer        |
| Refund reentrancy      | User marked refunded before transfer |

### State Transition Guards

- `disperseRewards()` only in `WinnerDrawn` state
- Double dispersal prevented
- Double refund prevented
- Double prize refund prevented

---

## Error Reference

### Entry Errors

| Error                         | Cause                          |
| ----------------------------- | ------------------------------ |
| `EntriesPurchaseClosed`       | Deadline reached               |
| `EntriesPurchaseInvalidValue` | Wrong payment amount           |
| `MaxUserEntriesReached`       | Exceeded entry limit           |
| `TokenGateRestriction`        | Doesn't meet gate requirements |

### VRF Errors

| Error                   | Cause                            |
| ----------------------- | -------------------------------- |
| `VRFRequestNotPending`  | Cannot retry when not pending    |
| `VRFRequestNotTimedOut` | Cannot emergency fail before 24h |
| `InvalidVRFRequest`     | No VRF tracking for raffle       |

### Refund Errors

| Error                            | Cause                |
| -------------------------------- | -------------------- |
| `RefundsOnlyAllowedOnFailedDraw` | Wrong game state     |
| `UserWithoutEntries`             | No entries to refund |
| `UserAlreadyRefunded`            | Already claimed      |
| `PrizesAlreadyRefunded`          | Already reclaimed    |

### Fee Errors

| Error                     | Cause                  |
| ------------------------- | ---------------------- |
| `InsufficientCreationFee` | Not enough ETH         |
| `FeeOutOfRange`           | Outside min/max bounds |
| `NotFeeCollector`         | Wrong caller           |

### Prize Errors

| Error                    | Cause              |
| ------------------------ | ------------------ |
| `NoPrizesProvided`       | Empty prizes array |
| `ERC20PrizeAmountIsZero` | Zero amount ERC20  |
| `DeadlineIsNotFuture`    | Past deadline      |

---

## Events

### Factory Events

- `RaffleCreated(address raffle)`
- `VRFRequestRetried(address indexed raffle, uint256 indexed requestId)`
- `RaffleEmergencyFailed(address indexed raffle)`
- `FeeCollectorChange(address indexed feeCollector)`
- `Global*FeeChange(uint64 value)`
- `Custom*FeeChange(address indexed user, uint64 value)`

### Raffle Events

- `RaffleInitialized()`
- `EntriesBought(address indexed user, uint256 entriesBought, uint256 value)`
- `EntriesRefunded(address indexed user, uint256 entriesRefunded, uint256 value)`
- `PrizesRefunded()`
- `WinnerDrawn(uint256 indexed requestId, uint256 winnerEntry, address user, uint256 entries)`
- `RewardsDispersed(address indexed winner)`
- `DeadlineSuccessCriteria(uint256 indexed requestId, uint256 entries, uint256 minEntries)`
- `DeadlineFailedCriteria(uint256 entries, uint256 minEntries)`

---

## Integration Lifecycle Scenarios

### Success Path

```
Initialized → [buyEntries()] → Deadline Reached →
DrawStarted (VRF requested) → WinnerDrawn (VRF fulfilled) →
disperseRewards() → SuccessDraw (COMPLETE)
```

### Failure Path: Criteria Not Met

```
Initialized → [Insufficient Entries] → Deadline Reached →
FailedDraw → refundEntries() / refundPrizes()
```

### Failure Path: VRF Timeout

```
Initialized → [buyEntries()] → Deadline Reached →
DrawStarted → [24h timeout] → emergencyFailRaffle() →
FailedDraw → refundEntries() / refundPrizes()
```

### VRF Recovery Path

```
DrawStarted → [VRF stuck/slow] → retryVRFRequest() →
[New VRF request] → WinnerDrawn → SuccessDraw
```

### Concurrent Raffles

- Multiple raffles can run simultaneously
- Each tracks its own VRF request independently
- VRF responses correctly routed via request ID mapping

---

## Automation Integration

### checkUpkeep() Returns True When

1. Raffle deadline reached AND upkeep not performed
2. Winner drawn AND dispersal pending

### performUpkeep() Actions

| Condition                   | Action                       |
| --------------------------- | ---------------------------- |
| Deadline + criteria met     | Request VRF, set DrawStarted |
| Deadline + criteria not met | Set FailedDraw               |
| Winner drawn                | Trigger disperseRewards()    |

---

## Test Coverage Reference

| Category        | Test Files                                                   |
| --------------- | ------------------------------------------------------------ |
| Token Gating    | `Raffl.TokenGating.t.sol`                                    |
| Entries         | `Raffl.EntriesEdgeCases.t.sol`, `Raffl.FreeEntries.t.sol`    |
| VRF             | `Raffl.VRFEdgeCases.t.sol`, `RafflFactory.VRFRetry.t.sol`    |
| Fees            | `Raffl.CustomPoolFee.t.sol`, `Raffl.CustomCreationFee.t.sol` |
| Access Control  | `RafflFactory.AccessControl.t.sol`                           |
| Security        | `Raffl.Security.t.sol`                                       |
| Prizes          | `Raffl.ERC721Prizes.t.sol`                                   |
| Extra Recipient | `Raffl.ExtraRecipientEdgeCases.t.sol`                        |
| Refunds         | `Raffl.RefundsWithNativeEntries.t.sol`                       |
| Integration     | `Raffl.Integration.t.sol`                                    |
| Initialization  | `Raffl.Initialize.t.sol`                                     |
| Fuzz Testing    | `Raffl.Fuzz.t.sol`                                           |
