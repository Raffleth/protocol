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

| Constant              | Value           | Description                   |
| --------------------- | --------------- | ----------------------------- |
| `MAX_POOL_FEE`        | 10% (0.1 ether) | Maximum pool fee              |
| `VRF_REQUEST_TIMEOUT` | 24 hours        | VRF recovery timeout          |
| `FEE_CHANGE_DELAY`    | 1 hour          | Time before fee changes apply |
| `ONE`                 | 1 ether         | 100% representation           |

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
