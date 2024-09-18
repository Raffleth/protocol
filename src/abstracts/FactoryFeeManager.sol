// SPDX-License-Identifier: None
// Raffl Protocol (last updated v1.0.0) (abstracts/FactoryFeeManager.sol)
pragma solidity ^0.8.27;

import { Errors } from "../libraries/RafflFactoryErrors.sol";
import { IFeeManager } from "../interfaces/IFeeManager.sol";
import { IFactoryFeeManager } from "../interfaces/IFactoryFeeManager.sol";

/// @title FactoryFeeManager
/// @notice See the documentation in {IFactoryFeeManager}.
/// @author JA (@ubinatus)
abstract contract FactoryFeeManager is IFactoryFeeManager {
    /**
     *
     * CONSTANTS
     *
     */

    /// @dev Pool fee is calculated using 18 decimals where 0.05 ether is 5%.
    uint64 internal constant MAX_POOL_FEE = 0.1 ether;

    /**
     *
     * STATE
     *
     */

    /// @dev Stores fee related information for collection purposes.
    FeeData internal _feeData;

    /// @dev Stores the info necessary for an upcoming change of the global creation fee.
    UpcomingFeeData internal _upcomingCreationFee;

    /// @dev Stores the info necessary for an upcoming change of the global pool fee.
    UpcomingFeeData internal _upcomingPoolFee;

    /// @dev Maps a user address to a custom creation fee struct.
    mapping(address => CustomFeeData) internal _creationFeeByUser;

    /// @dev Maps a user address to a custom pool fee struct.
    mapping(address => CustomFeeData) internal _poolFeeByUser;

    /// @notice Reverts if called by anyone other than the factory fee collector.
    modifier onlyFeeCollector() {
        if (msg.sender != _feeData.feeCollector) {
            revert Errors.NotFeeCollector();
        }
        _;
    }

    /**
     *
     * FUNCTIONS
     *
     */

    /// @inheritdoc IFactoryFeeManager
    function minPoolFee() external pure override returns (uint64) {
        return 0;
    }

    /// @inheritdoc IFactoryFeeManager
    function maxPoolFee() external pure override returns (uint64) {
        return MAX_POOL_FEE;
    }

    /// @inheritdoc IFactoryFeeManager
    function feeCollector() external view override returns (address) {
        return _feeData.feeCollector;
    }

    /// @inheritdoc IFactoryFeeManager
    function globalCreationFee() external view override returns (uint64) {
        return block.timestamp >= _upcomingCreationFee.valueChangeAt
            ? _upcomingCreationFee.nextValue
            : _feeData.creationFee;
    }

    /// @inheritdoc IFactoryFeeManager
    function globalPoolFee() external view override returns (uint64) {
        return
            block.timestamp >= _upcomingPoolFee.valueChangeAt ? _upcomingPoolFee.nextValue : _feeData.poolFeePercentage;
    }

    /// @inheritdoc IFeeManager
    function creationFeeData(address user)
        external
        view
        returns (address feeCollectorAddress, uint64 creationFeeValue)
    {
        feeCollectorAddress = _feeData.feeCollector;
        creationFeeValue = _getCurrentFee(_feeData.creationFee, _upcomingCreationFee, _creationFeeByUser[user]);
    }

    /// @notice Returns the current pool fee for a specific Raffle, considering any pending updates.
    /// @param user Address of the user.
    function poolFeeData(address user) external view returns (address feeCollectorAddress, uint64 poolFeePercentage) {
        feeCollectorAddress = _feeData.feeCollector;
        poolFeePercentage = _getCurrentFee(_feeData.poolFeePercentage, _upcomingPoolFee, _poolFeeByUser[user]);
    }

    /// @inheritdoc IFactoryFeeManager
    function scheduleGlobalCreationFee(uint64 newFeeValue) external override onlyFeeCollector {
        if (_upcomingCreationFee.valueChangeAt <= block.timestamp) {
            _feeData.creationFee = _upcomingCreationFee.nextValue;
        }

        _upcomingCreationFee.nextValue = newFeeValue;
        _upcomingCreationFee.valueChangeAt = uint64(block.timestamp + 1 hours);

        emit GlobalCreationFeeChange(newFeeValue);
    }

    /// @inheritdoc IFactoryFeeManager
    function scheduleGlobalPoolFee(uint64 newFeePercentage) external override onlyFeeCollector {
        if (newFeePercentage > MAX_POOL_FEE) revert Errors.FeeOutOfRange();

        _upcomingPoolFee.nextValue = newFeePercentage;
        _upcomingPoolFee.valueChangeAt = uint64(block.timestamp + 1 hours);

        emit GlobalPoolFeeChange(newFeePercentage);
    }

    /// @inheritdoc IFactoryFeeManager
    function scheduleCustomCreationFee(address user, uint64 newFeeValue) external override onlyFeeCollector {
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
    function scheduleCustomPoolFee(address user, uint64 newFeePercentage) external override onlyFeeCollector {
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
    function toggleCustomCreationFee(address user, bool enable) external override onlyFeeCollector {
        CustomFeeData storage customFee = _creationFeeByUser[user];

        if (customFee.statusChangeAt <= block.timestamp) {
            customFee.isEnabled = customFee.nextEnableState;
        }

        customFee.nextEnableState = enable;
        customFee.statusChangeAt = uint64(block.timestamp + 1 hours);

        emit CustomCreationFeeToggle(user, enable);
    }

    /// @inheritdoc IFactoryFeeManager
    function toggleCustomPoolFee(address user, bool enable) external override onlyFeeCollector {
        CustomFeeData storage customFee = _poolFeeByUser[user];

        if (customFee.statusChangeAt <= block.timestamp) {
            customFee.isEnabled = customFee.nextEnableState;
        }

        customFee.nextEnableState = enable;
        customFee.statusChangeAt = uint64(block.timestamp + 1 hours);

        emit CustomPoolFeeToggle(user, enable);
    }

    /// @notice Calculates the current fee based on global, custom, and upcoming fee data.
    /// @dev This function considers the current timestamp and determines the appropriate fee
    /// based on whether a custom or upcoming fee should be applied.
    /// @param globalValue The default global fee value used when no custom fees are applicable.
    /// @param upcomingGlobalFee A struct containing data about an upcoming fee change, including the timestamp
    /// for the change and the new value to be applied.
    /// @param customFee A struct containing data about the custom fee, including its enablement status,
    /// timestamps for changes, and its values (current and new).
    /// @return currentValue The calculated current fee value, taking into account the global value,
    /// custom fee, and upcoming fee data based on the current timestamp.
    function _getCurrentFee(
        uint64 globalValue,
        UpcomingFeeData memory upcomingGlobalFee,
        CustomFeeData memory customFee
    )
        internal
        view
        returns (uint64 currentValue)
    {
        if (block.timestamp >= customFee.statusChangeAt) {
            // If isCustomFee is true based on status, directly return the value based on the customFee conditions.
            if (customFee.nextEnableState) {
                return block.timestamp >= customFee.valueChangeAt ? customFee.nextValue : customFee.value;
            }
        } else if (customFee.isEnabled) {
            // This block handles the case where current timestamp is not past statusChangeAt, but custom is enabled.
            return block.timestamp >= customFee.valueChangeAt ? customFee.nextValue : customFee.value;
        }

        // If none of the custom fee conditions apply, return the global or upcoming fee value.
        return block.timestamp >= upcomingGlobalFee.valueChangeAt ? upcomingGlobalFee.nextValue : globalValue;
    }

    /// @notice Processes the creation fee for a transaction.
    /// @dev This function retrieves the creation fee data from the manager contract and, if the creation fee is greater
    /// than zero, sends the `msg.value` to the fee collector address. Reverts if the transferred value is less than the
    /// required creation fee or if the transfer fails.
    function _processCreationFee(address user) internal {
        uint64 creationFeeValue = _getCurrentFee(_feeData.creationFee, _upcomingCreationFee, _creationFeeByUser[user]);

        if (creationFeeValue != 0) {
            if (msg.value < creationFeeValue) revert Errors.InsufficientCreationFee();

            bytes4 unsuccessfulClaimFeeTransfer = Errors.UnsuccessfulCreationFeeTransfer.selector;
            address feeCollectorAddress = _feeData.feeCollector;

            assembly {
                let ptr := mload(0x40)
                let sendSuccess := call(gas(), feeCollectorAddress, callvalue(), 0x00, 0x00, 0x00, 0x00)
                if iszero(sendSuccess) {
                    mstore(ptr, unsuccessfulClaimFeeTransfer)
                    revert(ptr, 0x04)
                }
            }
        }
    }
}
