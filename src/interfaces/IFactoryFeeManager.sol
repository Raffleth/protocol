// SPDX-License-Identifier: None
// Raffl Protocol (last updated v1.0.0) (interfaces/FactoryFeeManager.sol)
pragma solidity ^0.8.27;

import { IFeeManager } from "./IFeeManager.sol";

/// @title IFactoryFeeManager
/// @dev Interface that describes the struct and accessor function for the data related to the collection of fees.
interface IFactoryFeeManager is IFeeManager {
    /**
     *
     * EVENTS
     *
     */

    /// @param feeCollector Address of the new fee collector.
    event FeeCollectorChange(address indexed feeCollector);

    /// @param creationFeeValue Value for the new creation fee.
    event GlobalCreationFeeChange(uint64 creationFeeValue);

    /// @param poolFeePercentage Value for the new pool fee.
    event GlobalPoolFeeChange(uint64 poolFeePercentage);

    /// @param user Address of the user.
    /// @param creationFeeValue Value for the new creation fee.
    event CustomCreationFeeChange(address indexed user, uint64 creationFeeValue);

    /// @param user Address of the user.
    /// @param enable Indicates the enabled state of the fee.
    event CustomCreationFeeToggle(address indexed user, bool enable);

    /// @param user Address of the user.
    /// @param poolFeePercentage Value for the new pool fee.
    event CustomPoolFeeChange(address indexed user, uint64 poolFeePercentage);

    /// @param user Address of the user.
    /// @param enable Indicates the enabled state of the fee.
    event CustomPoolFeeToggle(address indexed user, bool enable);

    /**
     *
     * FUNCTIONS
     *
     */

    /// @dev Set address of fee collector.
    ///
    /// Requirements:
    ///
    /// - `msg.sender` has to be the owner of the factory.
    /// - `newFeeCollector` can't be address 0x0.
    ///
    /// @param newFeeCollector Address of `feeCollector`.
    ///
    function setFeeCollector(address newFeeCollector) external;

    /// @notice Sets a new global creation fee value, to take effect after 1 hour.
    /// @dev `msg.sender` has to be the fee collector of the factory.
    /// @param newFeeValue Value for `creationFee` that will be charged on `Raffl`'s deployments.
    function scheduleGlobalCreationFee(uint64 newFeeValue) external;

    /// @notice Sets a new global pool fee percentage, to take effect after 1 hour.
    ///
    /// @dev Percentages and fees are calculated using 18 decimals where 1 ether is 100%.
    ///
    /// Requirements:
    ///
    /// - `newFeePercentage` must be within minPoolFee and maxPoolFee.
    /// - `msg.sender` has to be the fee collector of the factory.
    ///
    /// @param newFeePercentage Value for `poolFeePercentage` that will be charged on `Raffl`'s pools.
    function scheduleGlobalPoolFee(uint64 newFeePercentage) external;

    /// @notice Sets a new custom creation fee value for a specific User, to be enabled and take effect
    /// after 1 hour from the time of this transaction.
    ///
    /// @dev Allows the contract owner to modify the creation fee associated with a specific User.
    /// The new fee becomes effective after a delay of 1 hour, aiming to provide a buffer for users to be aware of the
    /// upcoming fee change.
    /// This function updates the fee and schedules its activation, ensuring transparency and predictability in fee
    /// adjustments.
    /// The fee is specified in wei, allowing for granular control over the fee structure. Emits a
    /// `CustomCreationFeeChange` event upon successful fee update.
    ///
    /// Requirements:
    /// - `msg.sender` has to be the fee collector of the factory.
    ///
    /// @param user Address of the `user`.
    /// @param newFeeValue The new creation fee amount to be set, in wei, to replace the current fee after the specified
    /// delay.
    function scheduleCustomCreationFee(address user, uint64 newFeeValue) external;

    /// @notice Sets a new custom pool fee percentage for a specific User, to be enabled and take effect
    /// after 1 hour from the time of this transaction.
    ///
    /// @dev This function allows the contract owner to adjust the pool fee for a User.
    /// The fee adjustment is delayed by 1 hour to provide transparency and predictability. Fees are calculated with
    /// precision to 18 decimal places, where 1 ether equals 100% fee.
    /// The function enforces fee limits; `newFeePercentage` must be within the predefined 0-`MAX_POOL_FEE` bounds.
    /// If the custom fee was previously disabled or set to a different value, this operation schedules the new fee to
    /// take effect after the delay, enabling it if necessary.
    /// Emits a `CustomPoolFeeChange` event upon successful execution.
    ///
    /// Requirements:
    /// - `msg.sender` has to be the fee collector of the factory.
    /// - `newFeePercentage` must be within the range limited by `MAX_POOL_FEE`.
    ///
    /// @param user Address of the `user`.
    /// @param newFeePercentage The new pool fee percentage to be applied, expressed in ether terms (18 decimal
    /// places) where 1 ether represents 100%.
    function scheduleCustomPoolFee(address user, uint64 newFeePercentage) external;

    /// @notice Enables or disables the custom creation fee for a given Raffle, with the change taking effect
    /// after 1 hour.
    /// @dev `msg.sender` has to be the fee collector of the factory.
    /// @param user Address of the `user`.
    /// @param enable True to enable the fee, false to disable it.
    function toggleCustomCreationFee(address user, bool enable) external;

    /// @notice Enables or disables the custom pool fee for a given Raffle, to take effect after 1 hour.
    /// @dev `msg.sender` has to be the fee collector of the factory.
    /// @param user Address of the `user`.
    /// @param enable True to enable the fee, false to disable it.
    function toggleCustomPoolFee(address user, bool enable) external;

    /// @dev Exposes the minimum pool fee.
    function minPoolFee() external pure returns (uint64);

    /// @dev Exposes the maximum pool fee.
    function maxPoolFee() external pure returns (uint64);

    /// @notice Exposes the `FeeData.feeCollector` to users.
    function feeCollector() external view returns (address);

    /// @notice Retrieves the current global creation fee to users.
    function globalCreationFee() external view returns (uint64);

    /// @notice Retrieves the current global pool fee percentage to users.
    function globalPoolFee() external view returns (uint64);

    /// @notice Returns the current creation fee for a specific user, considering any pending updates.
    /// @param user Address of the `user`.
    function creationFeeData(address user)
        external
        view
        override
        returns (address feeCollectorAddress, uint64 creationFeeValue);

    /// @notice Returns the current pool fee for a specific user, considering any pending updates.
    /// @param user Address of the `user`.
    function poolFeeData(address user)
        external
        view
        override
        returns (address feeCollectorAddress, uint64 poolFeePercentage);
}
