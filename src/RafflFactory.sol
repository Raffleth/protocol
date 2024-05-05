// SPDX-License-Identifier: None
// Raffl Protocol (last updated v1.0.0) (RafflFactory.sol)
pragma solidity ^0.8.25;

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
    /// @dev Max gas to bump to
    bytes32 keyHash;

    /// @dev Callback gas limit for the Chainlink VRF
    uint32 callbackGasLimit = 500_000;

    /// @dev Number of requests confirmations for the Chainlink VRF
    uint16 requestConfirmations = 3;

    /// @dev Chainlink subscription ID
    uint256 public subscriptionId;

    /// @param raffle Address of the created raffle
    event RaffleCreated(address raffle);

    /// @notice The address that will be used as a delegate call target for `Raffl`s.
    address public immutable implementation;

    /// @dev It will be used as the salt for create2
    bytes32 internal _salt;

    /// @dev Maps the created `Raffl`s addresses
    mapping(address => bool) internal _raffles;

    /// @dev Maps the VRF `requestId` to the `Raffl`s address
    mapping(uint256 => address) internal _requestIds;

    /// @dev `raffle` the address of the raffle
    /// @dev `deadline` is the timestamp that marks the start time to perform the upkeep effect.
    struct ActiveRaffle {
        address raffle;
        uint256 deadline;
    }

    /// @dev Stores the active raffles, which upkeep is pending to be performed
    ActiveRaffle[] internal _activeRaffles;

    /**
     * @dev Creates a `Raffl` factory contract.
     *
     * Requirements:
     *
     * - `implementationAddress` has to be a contract.
     * - `feeCollectorAddress` can't be address 0x0.
     * - `feePercentageValue` must be within 0 and maxFee range.
     * - `vrfCoordinator` can't be address 0x0.
     *
     * @param implementationAddress Address of `Raffl` contract implementation.
     * @param feeCollectorAddress   Address of `feeCollector`.
     * @param creationFeeValue    Value for `creationFee` that will be charged on new `Raffl`s deployed.
     * @param poolFeePercentage    Value for `feePercentage` that will be charged from the `Raffl`'s pool on success
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
        if (vrfCoordinator == address(0)) revert Errors.AddressCanNotBeZero();

        bytes32 seed;
        assembly ("memory-safe") {
            seed := chainid()
        }
        _salt = seed;

        implementation = implementationAddress;
        setFeeCollector(feeCollectorAddress);
        scheduleGlobalCreationFee(creationFeeValue);
        scheduleGlobalPoolFee(poolFeePercentage);
        _feeData.creationFee = creationFeeValue;
        _feeData.poolFeePercentage = poolFeePercentage;

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
        public
        returns (address raffle)
    {
        if (prizes.length == 0) revert Errors.PrizesIsEmpty();
        if (block.timestamp >= deadline) revert Errors.DeadlineIsNotFuture();

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

        IRaffl(raffle).initialize(
            entryToken, entryPrice, minEntries, deadline, msg.sender, prizes, tokenGates, extraRecipient
        );

        for (uint256 i = 0; i < prizes.length; ++i) {
            if (prizes[i].assetType == IRaffl.AssetType.ERC20 && prizes[i].value == 0) {
                revert Errors.ERC20PrizeAmountIsZero();
            }
            (bool success,) = prizes[i].asset.call(
                abi.encodeWithSignature("transferFrom(address,address,uint256)", msg.sender, raffle, prizes[i].value)
            );
            if (!success) revert Errors.UnsuccessfulTransferFromPrize();
        }

        _raffles[raffle] = true;
        _activeRaffles.push(ActiveRaffle(raffle, deadline));
        emit RaffleCreated(raffle);
    }

    /// @notice Exposes the `ActiveRaffle`s
    function activeRaffles() public view returns (ActiveRaffle[] memory) {
        return _activeRaffles;
    }

    /// @notice Sets the Chainlink VRF subscription settings
    /// @param _subscriptionId The subscription ID that this contract uses for funding VRF requests
    /// @param _keyHash The gas lane to use, which specifies the maximum gas price to bump to
    /// @param _callbackGasLimit Callback gas limit for the Chainlink VRF
    /// @param _requestConfirmations Number of requests confirmations for the Chainlink VRF
    function handleSubscription(
        uint64 _subscriptionId,
        bytes32 _keyHash,
        uint32 _callbackGasLimit,
        uint16 _requestConfirmations
    )
        external
        onlyOwner
    {
        subscriptionId = _subscriptionId;
        keyHash = _keyHash;
        callbackGasLimit = _callbackGasLimit;
        requestConfirmations = _requestConfirmations;
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
            if (_activeRaffles[lowerBound + i].deadline <= block.timestamp) {
                index = lowerBound + i;
                raffle = _activeRaffles[lowerBound + i].raffle;
                break;
            }
        }
        if (_raffles[raffle] && !IRaffl(raffle).upkeepPerformed()) {
            upkeepNeeded = true;
        }
        performData = abi.encode(raffle, index);
    }

    /// @notice Permisionless write method usually called by the Chainlink Automation Nodes.
    /// @dev Either starts the draw for a raffle or cancels the raffle if criteria is not met.
    /// @param performData Encoded binary data which contains the raffle address and index of the `_activeRaffles`
    function performUpkeep(bytes calldata performData) external override {
        (address raffle, uint256 index) = abi.decode(performData, (address, uint256));
        if (_activeRaffles.length <= index) revert Errors.UpkeepConditionNotMet();
        if (_activeRaffles[index].raffle != raffle) revert Errors.UpkeepConditionNotMet();
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
                    extraArgs: VRFV2PlusClient._argsToBytes(VRFV2PlusClient.ExtraArgsV1({ nativePayment: false }))
                })
            );
            IRaffl(raffle).setSuccessCriteria(requestId);
            _requestIds[requestId] = raffle;
        } else {
            IRaffl(raffle).setFailedCriteria();
        }
        _burnActiveRaffle(index);
    }

    /// @notice Method called by the Chainlink VRF Coordinator
    /// @param requestId Id of the VRF request
    /// @param randomWords Provably fair and verifiable array of random words
    function fulfillRandomWords(uint256 requestId, uint256[] memory randomWords) internal override {
        IRaffl(_requestIds[requestId]).disperseRewards(requestId, randomWords[0]);
    }

    /// @notice Helper function to remove a raffle from the `_activeRaffles` array
    /// @dev Move the last element to the deleted stop and removes the last element
    /// @param i Element index to remove
    function _burnActiveRaffle(uint256 i) internal {
        if (i >= _activeRaffles.length) revert Errors.ActiveRaffleIndexOutOfBounds();
        _activeRaffles[i] = _activeRaffles[_activeRaffles.length - 1];
        _activeRaffles.pop();
    }

    /// @inheritdoc IFactoryFeeManager
    function setFeeCollector(address newFeeCollector) public override onlyOwner {
        if (newFeeCollector == address(0)) revert Errors.AddressCanNotBeZero();

        _feeData.feeCollector = newFeeCollector;
        emit FeeCollectorChange(newFeeCollector);
    }

    /// @inheritdoc IFactoryFeeManager
    function scheduleGlobalCreationFee(uint64 newFeeValue) public override onlyOwner {
        if (_upcomingCreationFee.valueChangeAt <= block.timestamp) {
            _feeData.creationFee = _upcomingCreationFee.nextValue;
        }

        _upcomingCreationFee.nextValue = newFeeValue;
        _upcomingCreationFee.valueChangeAt = uint64(block.timestamp + 1 hours);

        emit GlobalCreationFeeChange(newFeeValue);
    }

    /// @inheritdoc IFactoryFeeManager
    function scheduleGlobalPoolFee(uint64 newFeePercentage) public override onlyOwner {
        if (newFeePercentage > MAX_POOL_FEE) revert Errors.FeeOutOfRange();

        _upcomingPoolFee.nextValue = newFeePercentage;
        _upcomingPoolFee.valueChangeAt = uint64(block.timestamp + 1 hours);

        emit GlobalPoolFeeChange(newFeePercentage);
    }

    /// @inheritdoc IFactoryFeeManager
    function scheduleCustomCreationFee(address user, uint64 newFeeValue) external override onlyOwner {
        CustomFeeData storage customFee = _creationFeeByUser[user];

        if (customFee.valueChangeAt <= block.timestamp) {
            customFee.value = customFee.nextValue;
        }

        uint64 ts = uint64(block.timestamp + 1 hours);

        customFee.nextEnableState = true;
        customFee.statusChangeAt = ts;
        customFee.nextValue = newFeeValue;
        customFee.valueChangeAt = ts;

        emit CustomCreationFeeChange(user, newFeeValue);
    }

    /// @inheritdoc IFactoryFeeManager
    function scheduleCustomPoolFee(address user, uint64 newFeePercentage) external override onlyOwner {
        if (newFeePercentage > MAX_POOL_FEE) revert Errors.FeeOutOfRange();

        CustomFeeData storage customFee = _poolFeeByUser[user];

        if (customFee.valueChangeAt <= block.timestamp) {
            customFee.value = customFee.nextValue;
        }

        uint64 ts = uint64(block.timestamp + 1 hours);

        customFee.nextEnableState = true;
        customFee.statusChangeAt = ts;
        customFee.nextValue = newFeePercentage;
        customFee.valueChangeAt = ts;

        emit CustomPoolFeeChange(user, newFeePercentage);
    }

    /// @inheritdoc IFactoryFeeManager
    function toggleCustomCreationFee(address user, bool enable) external override onlyOwner {
        CustomFeeData storage customFee = _creationFeeByUser[user];

        if (customFee.statusChangeAt <= block.timestamp) {
            customFee.isEnabled = customFee.nextEnableState;
        }

        customFee.nextEnableState = enable;
        customFee.statusChangeAt = uint64(block.timestamp + 1 hours);

        emit CustomCreationFeeToggle(user, enable);
    }

    /// @inheritdoc IFactoryFeeManager
    function toggleCustomPoolFee(address user, bool enable) external override onlyOwner {
        CustomFeeData storage customFee = _poolFeeByUser[user];

        if (customFee.statusChangeAt <= block.timestamp) {
            customFee.isEnabled = customFee.nextEnableState;
        }

        customFee.nextEnableState = enable;
        customFee.statusChangeAt = uint64(block.timestamp + 1 hours);

        emit CustomPoolFeeToggle(user, enable);
    }
}
