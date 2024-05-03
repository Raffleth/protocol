// SPDX-License-Identifier: None
// Raffl Protocol (last updated v1.0.0) (RafflFactory.sol)
pragma solidity ^0.8.25;

import { VRFV2PlusClient } from "@chainlink/contracts/src/v0.8/vrf/dev/libraries/VRFV2PlusClient.sol";
import { VRFConsumerBaseV2Plus } from "@chainlink/contracts/src/v0.8/vrf/dev/VRFConsumerBaseV2Plus.sol";
import { AutomationCompatibleInterface } from "@chainlink/contracts/src/v0.8/automation/AutomationCompatible.sol";

import { Errors } from "./libraries/RafflFactoryErrors.sol";

import { IRaffl } from "./interfaces/IRaffl.sol";
import { IFeeManager } from "./interfaces/IFeeManager.sol";

/*
                                                                       
  _____            ______ ______ _      
 |  __ \     /\   |  ____|  ____| |     
 | |__) |   /  \  | |__  | |__  | |     
 |  _  /   / /\ \ |  __| |  __| | |     
 | | \ \  / ____ \| |    | |    | |____ 
 |_|  \_\/_/    \_\_|    |_|    |______|                               
                                                                       
 */

/// @title RafflFactory
/// @dev The RafflFactory contract can be used to create raffle contracts
contract RafflFactory is AutomationCompatibleInterface, VRFConsumerBaseV2Plus, IFeeManager {
    /// @dev Max gas to bump to
    bytes32 keyHash;

    /// @dev Callback gas limit for the Chainlink VRF
    uint32 callbackGasLimit = 500_000;

    /// @dev Number of requests confirmations for the Chainlink VRF
    uint16 requestConfirmations = 3;

    /// @dev Chainlink subscription ID
    uint256 public subscriptionId;

    /// @dev `feePercentage` is the new fee percentage that will be valid to be executed after `validFrom`.
    /// @dev `feePenality` is the new fee penality that will be valid to be executed after `validFrom`.
    /// @dev `validFrom` is the timestamp that marks the point in time where proposal can be executed.
    struct ProposedFee {
        uint64 feePercentage;
        uint256 feePenality;
        uint64 validFrom;
    }

    /// @dev `enabled` is the boolean which indicates if the individual `Raffl` fee should be applied
    /// @dev `feePercentage` is the percentage of every transaction that will be collected.
    struct RafflFeeData {
        bool enabled;
        uint64 feePercentage;
    }

    /// @param raffle Address of the created raffle
    event RaffleCreated(address raffle);

    /// @param feeCollector Address of the new fee collector.
    event FeeCollectorChanged(address indexed feeCollector);

    /// @param feePercentage Value for the new fee.
    /// @param feePenality Value for the new penality.
    event FeeProposal(uint64 feePercentage, uint256 feePenality);

    /// @param feePercentage Value for the new fee.
    /// @param feePenality Value for the new penality.
    event FeeChanged(uint64 feePercentage, uint256 feePenality);

    /// @param raffle Address of raffle with custom fee
    event RafflFeeChanged(address raffle);

    /// @dev Percentages and fees are calculated using 18 decimals where 0.05 ether is 5%.
    uint64 private constant MAX_FEE = 0.05 ether;

    /// @notice The address that will be used as a delegate call target for `Raffl`s.
    address public immutable implementation;

    /// @dev It will be used as the salt for create2
    bytes32 internal _salt;

    /// @dev Stores the address that will collect the fees of every success draw of `Raffl`s and the percentage that
    /// will be charged.
    FeeData internal _feeData;

    /// @dev Stores the info necessary for a proposal change of the fee structure.
    ProposedFee internal _proposedFee;

    /// @dev Maps the `Raffl` addresses that have custom fees.
    mapping(address => RafflFeeData) public customFees;

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
     * @param feePercentageValue    Value for `feePercentage` that will be charged on `Raffl`'s success draw.
     * @param vrfCoordinator VRF Coordinator address
     * @param _keyHash The gas lane to use, which specifies the maximum gas price to bump to
     * @param _subscriptionId The subscription ID that this contract uses for funding VRF requests
     */
    constructor(
        address implementationAddress,
        address feeCollectorAddress,
        uint64 feePercentageValue,
        uint256 feePenalityValue,
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
        proposeFeeChange(feePercentageValue, feePenalityValue);
        setFeeCollector(feeCollectorAddress);

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

    /**
     * @dev Set address of fee collector.
     *
     * Requirements:
     *
     * - `msg.sender` has to be the owner of the contract.
     * - `newFeeCollector` can't be address 0x0.
     *
     * @param newFeeCollector Address of `feeCollector`.
     */
    function setFeeCollector(address newFeeCollector) public onlyOwner {
        if (newFeeCollector == address(0)) revert Errors.AddressCanNotBeZero();

        _feeData.feeCollector = newFeeCollector;
        emit FeeCollectorChanged(newFeeCollector);
    }

    /**
     * @notice Proposes a new fee structure change.
     *
     * @dev Percentages and fees are calculated using 18 decimals where 1 ether is 100%.
     * @dev `newFeePercentage` must be within the range 0% - 5%.
     * @dev `newFeePenality` is the value of the penality in native tokens.
     *
     * Requirements:
     *
     * - `msg.sender` has to be `feeCollector`.
     * - `newFeePercentage` must be within 0 and maxFee range.
     *
     * @param newFeePercentage Value for `feePercentage` that will be charged on total pooled entried on successful
     * draws.
     * @param newFeePenality Value for `feePenality` that will be charged to the `Raffl` owner on failed draws.
     */
    function proposeFeeChange(uint64 newFeePercentage, uint256 newFeePenality) public {
        if (msg.sender != _feeData.feeCollector && _feeData.feeCollector != address(0)) {
            revert Errors.NotFeeCollector();
        }
        if (newFeePercentage > MAX_FEE) revert Errors.FeeOutOfRange();

        if (_feeData.feeCollector == address(0)) {
            _feeData.feePercentage = newFeePercentage;
            _feeData.feePenality = newFeePenality;
            emit FeeChanged(newFeePercentage, newFeePenality);
        } else {
            if (_feeData.feePercentage == newFeePercentage && _feeData.feePenality == newFeePenality) {
                revert Errors.FeeAlreadySet();
            }
            _proposedFee = ProposedFee(newFeePercentage, newFeePenality, uint64(block.timestamp + 1 hours));
            emit FeeProposal(newFeePercentage, newFeePenality);
        }
    }

    /**
     * @notice Executes the fee structure change proposal.
     *
     * Requirements:
     *
     * - `msg.sender` has to be `feeCollector`.
     * - 1 hour must have passed after the latest fee percentage change proposal.
     *
     */
    function executeFeeChange() public {
        if (_proposedFee.validFrom > block.timestamp) revert Errors.ProposalNotReady();
        if (_feeData.feePercentage == _proposedFee.feePercentage && _feeData.feePenality == _proposedFee.feePenality) {
            revert Errors.FeeAlreadySet();
        }

        _feeData.feePercentage = _proposedFee.feePercentage;
        _feeData.feePenality = _proposedFee.feePenality;

        emit FeeChanged(_feeData.feePercentage, _feeData.feePenality);
    }

    /**
     * @notice Updates the
     *
     * Requirements:
     *
     * - `msg.sender` has to be `feeCollector`.
     * - `fee` must be within 0 and maxFee range.
     *
     */
    function setRafflFee(address[] calldata raffles, bool enabled, uint64 fee) public {
        if (msg.sender != _feeData.feeCollector) revert Errors.NotFeeCollector();
        if (fee > MAX_FEE) revert Errors.FeeOutOfRange();

        for (uint256 i = 0; i < raffles.length; ++i) {
            if (!_raffles[raffles[i]]) revert Errors.NotARaffle();
            customFees[raffles[i]] = RafflFeeData(enabled, fee);
            emit RafflFeeChanged(raffles[i]);
        }
    }

    /// @dev Exposes MAX_FEE in a lowerCamelCase.
    function maxFee() external pure returns (uint64) {
        return MAX_FEE;
    }

    /// @notice Exposes the `FeeData.feeCollector` to users.
    function feeCollector() external view returns (address) {
        return _feeData.feeCollector;
    }

    /// @notice Exposes the `FeeData.feePercentage` to users.
    function feePercentage() external view returns (uint64) {
        return feeData().feePercentage;
    }

    /// @notice Exposes the `FeeData.feePenality` to users.
    function feePenality() external view returns (uint256) {
        return feeData().feePenality;
    }

    /// @notice Exposes the `FeeData`.
    function feeData() public view override returns (FeeData memory) {
        if (customFees[msg.sender].enabled) {
            return FeeData(_feeData.feeCollector, customFees[msg.sender].feePercentage, _feeData.feePenality);
        }
        return _feeData;
    }

    /// @notice Exposes the `ProposedFee`.
    function proposedFee() public view returns (ProposedFee memory) {
        return _proposedFee;
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
}
