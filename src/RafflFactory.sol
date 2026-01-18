// SPDX-License-Identifier: None
// Raffl Protocol (last updated v1.0.0) (RafflFactory.sol)
pragma solidity ^0.8.33;

import { VRFV2PlusClient } from "@chainlink/contracts/src/v0.8/vrf/dev/libraries/VRFV2PlusClient.sol";
import { VRFConsumerBaseV2Plus } from "@chainlink/contracts/src/v0.8/vrf/dev/VRFConsumerBaseV2Plus.sol";
import { AutomationCompatibleInterface } from "@chainlink/contracts/src/v0.8/automation/AutomationCompatible.sol";

import { Errors } from "./libraries/RafflFactoryErrors.sol";

import { FactoryFeeManager } from "./abstracts/FactoryFeeManager.sol";

import { IRaffl } from "./interfaces/IRaffl.sol";
import { IFactoryFeeManager } from "./interfaces/IFactoryFeeManager.sol";

/*

  _____            ______ ______ _
 |  __ \     /\   |  ____|  ____| |
 | |__) |   /  \  | |__  | |__  | |
 |  _  /   / /\ \ |  __| |  __| | |
 | | \ \  / ____ \| |    | |    | |____
 |_|  \_\/_/    \_\_|    |_|    |______|

 */

/// @title RafflFactory
/// @author JA (@ubinatus)
/// @notice Raffl is a decentralized platform built on the Ethereum blockchain, allowing users to create and participate
/// in raffles/lotteries with complete transparency, security, and fairness.
/// @dev The RafflFactory contract can be used to create raffle contracts, leveraging Chainlink VRF and Chainlink
/// Automations.
contract RafflFactory is AutomationCompatibleInterface, VRFConsumerBaseV2Plus, FactoryFeeManager {
    // ============ Gas-Optimized Storage Layout ============
    
    // Slot inherited from VRFConsumerBaseV2Plus: s_vrfCoordinator
    
    // ============ Slot X: VRF Config (packed) ============
    /// @dev Max gas to bump to
    bytes32 keyHash;
    
    // ============ Slot X+1: Chainlink subscription ID ============
    /// @dev Chainlink subscription ID
    uint256 public subscriptionId;
    
    // ============ Slot X+2: Packed VRF settings (7 bytes total) ============
    /// @dev Callback gas limit for the Chainlink VRF
    uint32 callbackGasLimit = 500_000;
    /// @dev Number of requests confirmations for the Chainlink VRF
    uint16 requestConfirmations = 3;
    /// @dev Whether to pay Chainlink fees with native token or LINK
    bool nativePayment = true;
    // 25 bytes remaining in this slot

    /// @param raffle Address of the created raffle
    event RaffleCreated(address raffle);

    /// @param raffle Address of the raffle
    /// @param requestId The VRF request ID
    event VRFRequestRetried(address indexed raffle, uint256 indexed requestId);

    /// @param raffle Address of the raffle
    event RaffleEmergencyFailed(address indexed raffle);

    /// @notice The address that will be used as a delegate call target for `Raffl`s.
    address public immutable implementation;

    /// @dev It will be used as the salt for create2
    bytes32 internal _salt;

    /// @dev Maps the created `Raffl`s addresses
    mapping(address => bool) internal _raffles;

    /// @dev Maps the VRF `requestId` to the `Raffl`s address
    mapping(uint256 => address) internal _requestIds;

    /// @dev Enum to track the status of VRF requests
    enum VRFStatus {
        None, // No request made
        Pending, // Request made, waiting for response
        Fulfilled, // Request fulfilled successfully
        Failed // Request failed or timed out
    }

    /// @dev Struct to store VRF request information (gas-optimized: 2 slots instead of 3)
    /// @dev requestTime as uint64 is sufficient until year 584 billion
    struct VRFRequest {
        uint256 requestId;      // slot 0: 32 bytes
        uint64 requestTime;     // slot 1: 8 bytes
        VRFStatus status;       // slot 1: 1 byte (packed with requestTime)
        // 23 bytes remaining in slot 1
    }

    /// @dev Maps raffle address to its VRF request information
    mapping(address => VRFRequest) internal _raffleVRFRequests;

    /// @dev Timeout duration for VRF requests (24 hours)
    uint256 public constant VRF_REQUEST_TIMEOUT = 24 hours;

    /// @dev `raffle` the address of the raffle
    /// @dev `deadline` is the timestamp that marks the start time to perform the upkeep effect.
    /// @dev Gas-optimized: deadline as uint64 (sufficient until year 584 billion)
    struct ActiveRaffle {
        address raffle;     // 20 bytes
        uint64 deadline;    // 8 bytes (packed with raffle in same slot)
        // 4 bytes remaining
    }

    /// @dev Stores the active raffles, which upkeep is pending to be performed
    ActiveRaffle[] internal _activeRaffles;
    
    /// @dev Maps raffle address to its index in _activeRaffles for O(1) removal
    mapping(address => uint256) internal _raffleToActiveIndex;

    /**
     * @dev Creates a `Raffl` factory contract.
     *
     * Requirements:
     *
     * - `implementationAddress` has to be a contract.
     * - `feeCollectorAddress` can't be address 0x0.
     * - `poolFeePercentage` must be within 0 and maxFee range.
     * - `vrfCoordinator` can't be address 0x0.
     *
     * @param implementationAddress Address of `Raffl` contract implementation.
     * @param feeCollectorAddress   Address of `feeCollector`.
     * @param creationFeeValue    Value for `creationFee` that will be charged on new `Raffl`s deployed.
     * @param poolFeePercentage    Value for `poolFeePercentage` that will be charged from the `Raffl`s pool on success
     * draw.
     * @param vrfCoordinator VRF Coordinator address
     * @param _keyHash The gas lane to use, which specifies the maximum gas price to bump to
     * @param _subscriptionId The subscription ID that this contract uses for funding VRF requests
     */
    constructor(
        address implementationAddress,
        address feeCollectorAddress,
        uint64 creationFeeValue,
        uint64 poolFeePercentage,
        address vrfCoordinator,
        bytes32 _keyHash,
        uint256 _subscriptionId
    )
        VRFConsumerBaseV2Plus(vrfCoordinator)
    {
        if (implementationAddress == address(0)) revert Errors.AddressCanNotBeZero();
        if (feeCollectorAddress == address(0)) revert Errors.AddressCanNotBeZero();
        if (vrfCoordinator == address(0)) revert Errors.AddressCanNotBeZero();
        if (poolFeePercentage > MAX_POOL_FEE) revert Errors.FeeOutOfRange();

        bytes32 seed;
        assembly ("memory-safe") {
            seed := chainid()
        }
        _salt = seed;

        implementation = implementationAddress;
        _feeData.feeCollector = feeCollectorAddress;
        _upcomingCreationFee.nextValue = creationFeeValue;
        _upcomingPoolFee.nextValue = poolFeePercentage;

        keyHash = _keyHash;
        subscriptionId = _subscriptionId;
    }

    /// @notice Increments the salt one step.
    function nextSalt() public {
        _salt = keccak256(abi.encode(_salt));
    }

    /**
     * @notice Creates new `Raffl` contracts.
     *
     * Requirements:
     *
     * - `underlyingTokenAddress` cannot be the zero address.
     * - `timestamps` must be given in ascending order.
     * - `percentages` must be given in ascending order and the last one must always be 1 eth, where 1 eth equals to
     * 100%.
     *
     * @param entryToken        The address of the ERC-20 token as entry. If address zero, entry is the network token
     * @param entryPrice        The value of each entry for the raffle.
     * @param minEntries        The minimum number of entries to consider make the draw.
     * @param deadline          The block timestamp until the raffle will receive entries
     *                          and that will perform the draw if criteria is met.
     * @param prizes            The prizes that will be held by this contract.
     * @param tokenGates        The token gating that will be imposed to users.
     * @param extraRecipient    The extra recipient that will share the rewards (optional).
     */
    function createRaffle(
        address entryToken,
        uint256 entryPrice,
        uint256 minEntries,
        uint256 deadline,
        IRaffl.Prize[] calldata prizes,
        IRaffl.TokenGate[] calldata tokenGates,
        IRaffl.ExtraRecipient calldata extraRecipient
    )
        external
        payable
        returns (address raffle)
    {
        if (block.timestamp >= deadline) revert Errors.DeadlineIsNotFuture();
        if (prizes.length == 0) revert Errors.NoPrizesProvided();

        address impl = implementation;
        bytes32 salt = _salt;

        // Deploys and returns the address of a clone that mimics the behaviour of `implementation`.
        assembly ("memory-safe") {
            // Cleans the upper 96 bits of the `implementation` word, then packs the first 3 bytes
            // of the `implementation` address with the bytecode before the address.
            mstore(0x00, or(shr(0xe8, shl(0x60, impl)), 0x3d602d80600a3d3981f3363d3d373d3d3d363d73000000))
            // Packs the remaining 17 bytes of `implementation` with the bytecode after the address.
            mstore(0x20, or(shl(0x78, impl), 0x5af43d82803e903d91602b57fd5bf3))
            raffle := create2(0, 0x09, 0x37, salt)
        }

        if (raffle == address(0)) revert Errors.FailedToDeploy();
        nextSalt();

        _processCreationFee(msg.sender);

        IRaffl(raffle)
            .initialize(entryToken, entryPrice, minEntries, deadline, msg.sender, prizes, tokenGates, extraRecipient);

        uint256 prizesLength = prizes.length;
        for (uint256 i = prizesLength; i != 0;) {
            unchecked {
                --i;
            }

            if (prizes[i].assetType == IRaffl.AssetType.ERC20 && prizes[i].value == 0) {
                revert Errors.ERC20PrizeAmountIsZero();
            }
            (bool success, bytes memory data) = prizes[i].asset
                .call(
                    abi.encodeWithSignature(
                        "transferFrom(address,address,uint256)", msg.sender, raffle, prizes[i].value
                    )
                );

            // Check success and decode return value properly
            if (!success || (data.length != 0 && !abi.decode(data, (bool)))) {
                revert Errors.UnsuccessfulTransferFromPrize();
            }
        }

        _raffles[raffle] = true;
        uint256 activeIndex = _activeRaffles.length;
        _activeRaffles.push(ActiveRaffle({ raffle: raffle, deadline: uint64(deadline) }));
        _raffleToActiveIndex[raffle] = activeIndex;
        emit RaffleCreated(raffle);
    }

    /// @notice Exposes the `_raffles` mapping
    function isRaffle(address raffle) public view returns (bool) {
        return _raffles[raffle];
    }

    /// @notice Exposes the `ActiveRaffle`s
    function activeRaffles() public view returns (ActiveRaffle[] memory) {
        return _activeRaffles;
    }

    /// @notice Gets the VRF request information for a raffle
    /// @param raffle The address of the raffle
    /// @return requestId The VRF request ID
    /// @return requestTime The timestamp when the request was made
    /// @return status The current status of the VRF request
    function getVRFRequestInfo(address raffle)
        public
        view
        returns (uint256 requestId, uint256 requestTime, VRFStatus status)
    {
        VRFRequest memory vrfRequest = _raffleVRFRequests[raffle];
        return (vrfRequest.requestId, vrfRequest.requestTime, vrfRequest.status);
    }

    /// @notice Checks if a VRF request has timed out
    /// @param raffle The address of the raffle
    /// @return Whether the VRF request has timed out
    function hasVRFRequestTimedOut(address raffle) public view returns (bool) {
        VRFRequest memory vrfRequest = _raffleVRFRequests[raffle];
        return vrfRequest.status == VRFStatus.Pending && block.timestamp >= vrfRequest.requestTime + VRF_REQUEST_TIMEOUT;
    }

    /// @notice Sets the Chainlink VRF subscription settings
    /// @param _subscriptionId The subscription ID that this contract uses for funding VRF requests
    /// @param _keyHash The gas lane to use, which specifies the maximum gas price to bump to
    /// @param _callbackGasLimit Callback gas limit for the Chainlink VRF
    /// @param _requestConfirmations Number of requests confirmations for the Chainlink VRF
    /// @param _nativePayment Whether to pay Chainlink fees with native token or LINK.
    function handleSubscription(
        uint64 _subscriptionId,
        bytes32 _keyHash,
        uint32 _callbackGasLimit,
        uint16 _requestConfirmations,
        bool _nativePayment
    )
        external
        onlyOwner
    {
        subscriptionId = _subscriptionId;
        keyHash = _keyHash;
        callbackGasLimit = _callbackGasLimit;
        requestConfirmations = _requestConfirmations;
        nativePayment = _nativePayment;
    }

    /**
     * @notice Method called by the Chainlink Automation Nodes to check if `performUpkeep` must be done.
     * @dev Performs the computation to the array of `_activeRaffles`. This opens the possibility of having several
     * checkUpkeeps done at the same time.
     * @param checkData Encoded binary data which contains the lower bound and upper bound of the `_activeRaffles` array
     * on which to perform the computation
     * @return upkeepNeeded Whether the upkeep must be performed or not
     * @return performData Encoded binary data which contains the raffle address and index of the `_activeRaffles`
     */
    function checkUpkeep(bytes calldata checkData)
        external
        view
        override
        returns (bool upkeepNeeded, bytes memory performData)
    {
        if (_activeRaffles.length == 0) revert Errors.NoActiveRaffles();
        (uint256 lowerBound, uint256 upperBound) = abi.decode(checkData, (uint256, uint256));
        if (lowerBound >= upperBound) revert Errors.InvalidLowerAndUpperBounds();
        // Compute the active raffle that needs to be settled
        uint256 index;
        address raffle;
        for (uint256 i = 0; i < upperBound - lowerBound + 1; ++i) {
            if (_activeRaffles.length <= lowerBound + i) break;
            address currentRaffle = _activeRaffles[lowerBound + i].raffle;

            // Check if raffle needs reward dispersal
            if (_raffles[currentRaffle] && IRaffl(currentRaffle).shouldDisperseRewards()) {
                index = lowerBound + i;
                raffle = currentRaffle;
                upkeepNeeded = true;
                break;
            }

            // Check if raffle deadline passed and upkeep not performed
            if (_activeRaffles[lowerBound + i].deadline <= block.timestamp) {
                if (_raffles[currentRaffle] && !IRaffl(currentRaffle).upkeepPerformed()) {
                    index = lowerBound + i;
                    raffle = currentRaffle;
                    upkeepNeeded = true;
                    break;
                }
            }
        }
        performData = abi.encode(raffle, index);
    }

    /// @notice Permissionless write method usually called by the Chainlink Automation Nodes.
    /// @dev Either starts the draw for a raffle, disperses rewards, or cancels the raffle if criteria is not met.
    /// @param performData Encoded binary data which contains the raffle address and index of the `_activeRaffles`
    function performUpkeep(bytes calldata performData) external override {
        (address raffle, uint256 index) = abi.decode(performData, (address, uint256));
        if (_activeRaffles.length <= index) revert Errors.UpkeepConditionNotMet();
        if (_activeRaffles[index].raffle != raffle) revert Errors.UpkeepConditionNotMet();

        // Check if raffle needs reward dispersal
        if (IRaffl(raffle).shouldDisperseRewards()) {
            IRaffl(raffle).disperseRewards();
            _removeRaffleFromActive(raffle);
            return;
        }

        // Check if raffle needs draw initiation
        if (_activeRaffles[index].deadline > block.timestamp) revert Errors.UpkeepConditionNotMet();
        if (IRaffl(raffle).upkeepPerformed()) revert Errors.UpkeepConditionNotMet();

        bool criteriaMet = IRaffl(raffle).criteriaMet();
        if (criteriaMet) {
            uint256 requestId = s_vrfCoordinator.requestRandomWords(
                VRFV2PlusClient.RandomWordsRequest({
                    keyHash: keyHash,
                    subId: subscriptionId,
                    requestConfirmations: requestConfirmations,
                    callbackGasLimit: callbackGasLimit,
                    numWords: 1,
                    extraArgs: VRFV2PlusClient._argsToBytes(
                        VRFV2PlusClient.ExtraArgsV1({ nativePayment: nativePayment })
                    )
                })
            );
            IRaffl(raffle).setSuccessCriteria(requestId);
            _requestIds[requestId] = raffle;

            // Store VRF request info for tracking and retry capability
            _raffleVRFRequests[raffle] =
                VRFRequest({ requestId: requestId, requestTime: uint64(block.timestamp), status: VRFStatus.Pending });

            // Do NOT burn the active raffle yet - keep it until rewards dispersed
        } else {
            IRaffl(raffle).setFailedCriteria();
            _burnActiveRaffle(index);
        }
    }

    /// @notice Method called by the Chainlink VRF Coordinator
    /// @param requestId Id of the VRF request
    /// @param randomWords Provably fair and verifiable array of random words
    function fulfillRandomWords(uint256 requestId, uint256[] calldata randomWords) internal override {
        address raffle = _requestIds[requestId];
        if (raffle == address(0)) revert Errors.InvalidVRFRequest();

        // Mark VRF request as fulfilled
        _raffleVRFRequests[raffle].status = VRFStatus.Fulfilled;

        // Set the winner (low gas operation, unlikely to fail)
        IRaffl(raffle).setWinner(requestId, randomWords[0]);

        // Note: Raffle stays in active list until rewards are dispersed
        // This will be handled by checkUpkeep/performUpkeep or manual disperseRewards call
    }

    /// @notice Manually disperse rewards after winner is drawn
    /// @dev Permissionless - anyone can call this to help complete the raffle
    /// @param raffle The address of the raffle to disperse rewards for
    function disperseRewards(address raffle) external {
        if (!_raffles[raffle]) revert Errors.InvalidVRFRequest();
        if (!IRaffl(raffle).shouldDisperseRewards()) revert Errors.UpkeepConditionNotMet();

        IRaffl(raffle).disperseRewards();
        _removeRaffleFromActive(raffle);
    }

    /// @notice Retry a failed or stuck VRF request
    /// @dev Can be called by anyone if the VRF request is in pending state
    /// @param raffle The address of the raffle to retry
    function retryVRFRequest(address raffle) external {
        if (!_raffles[raffle]) revert Errors.InvalidVRFRequest();

        VRFRequest storage vrfRequest = _raffleVRFRequests[raffle];
        if (vrfRequest.status != VRFStatus.Pending) revert Errors.VRFRequestNotPending();

        // Request new random words
        uint256 requestId = s_vrfCoordinator.requestRandomWords(
            VRFV2PlusClient.RandomWordsRequest({
                keyHash: keyHash,
                subId: subscriptionId,
                requestConfirmations: requestConfirmations,
                callbackGasLimit: callbackGasLimit,
                numWords: 1,
                extraArgs: VRFV2PlusClient._argsToBytes(VRFV2PlusClient.ExtraArgsV1({ nativePayment: nativePayment }))
            })
        );

        // Update with new request ID and timestamp
        _requestIds[requestId] = raffle;
        vrfRequest.requestId = requestId;
        vrfRequest.requestTime = uint64(block.timestamp);

        emit VRFRequestRetried(raffle, requestId);
    }

    /// @notice Emergency fallback to mark raffle as failed if VRF is stuck beyond timeout
    /// @dev Can be called by anyone after VRF_REQUEST_TIMEOUT has passed
    /// @param raffle The address of the raffle to mark as failed
    function emergencyFailRaffle(address raffle) external {
        if (!_raffles[raffle]) revert Errors.InvalidVRFRequest();

        VRFRequest storage vrfRequest = _raffleVRFRequests[raffle];
        if (vrfRequest.status != VRFStatus.Pending) revert Errors.VRFRequestNotPending();
        if (block.timestamp <= vrfRequest.requestTime + VRF_REQUEST_TIMEOUT) {
            revert Errors.VRFRequestNotTimedOut();
        }

        // Mark as failed
        vrfRequest.status = VRFStatus.Failed;

        // Set raffle to failed state so users can get refunds
        IRaffl(raffle).setFailedCriteria();

        // Remove from active raffles
        _removeRaffleFromActive(raffle);

        emit RaffleEmergencyFailed(raffle);
    }

    /// @notice Helper function to remove a raffle from the `_activeRaffles` array by address
    /// @dev O(1) removal using index mapping
    /// @param raffle The address of the raffle to remove
    function _removeRaffleFromActive(address raffle) internal {
        uint256 index = _raffleToActiveIndex[raffle];
        uint256 lastIndex = _activeRaffles.length - 1;
        
        // If not the last element, swap with last
        if (index != lastIndex) {
            ActiveRaffle memory lastRaffle = _activeRaffles[lastIndex];
            _activeRaffles[index] = lastRaffle;
            _raffleToActiveIndex[lastRaffle.raffle] = index;
        }
        
        // Remove last element and clean up mapping
        _activeRaffles.pop();
        delete _raffleToActiveIndex[raffle];
    }

    /// @notice Helper function to remove a raffle from the `_activeRaffles` array by index
    /// @dev Move the last element to the deleted slot and removes the last element
    /// @param i Element index to remove
    function _burnActiveRaffle(uint256 i) internal {
        if (i >= _activeRaffles.length) revert Errors.ActiveRaffleIndexOutOfBounds();
        
        address raffleAtIndex = _activeRaffles[i].raffle;
        uint256 lastIndex = _activeRaffles.length - 1;
        
        // If not the last element, swap with last and update mapping
        if (i != lastIndex) {
            ActiveRaffle memory lastRaffle = _activeRaffles[lastIndex];
            _activeRaffles[i] = lastRaffle;
            _raffleToActiveIndex[lastRaffle.raffle] = i;
        }
        
        // Remove last element and clean up mapping
        _activeRaffles.pop();
        delete _raffleToActiveIndex[raffleAtIndex];
    }

    /// @inheritdoc IFactoryFeeManager
    function setFeeCollector(address newFeeCollector) external override onlyOwner {
        if (newFeeCollector == address(0)) revert Errors.AddressCanNotBeZero();

        _feeData.feeCollector = newFeeCollector;
        emit FeeCollectorChange(newFeeCollector);
    }
}
