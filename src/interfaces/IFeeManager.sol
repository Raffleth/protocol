// SPDX-License-Identifier: None
// Raffl Protocol (last updated v1.0.0) (interfaces/IFeeManager.sol)
pragma solidity ^0.8.27;

/// @title IFeeManager
/// @dev Interface that describes the struct and accessor function for the data related to the collection of fees.
interface IFeeManager {
    /// @dev The `FeeData` struct is used to store fee configurations such as the collection address and fee amounts for
    /// various transaction types in the contract.
    struct FeeData {
        /// @notice The address designated to collect fees.
        /// @dev This address is responsible for receiving fees generated from various sources.
        address feeCollector;
        /// @notice The fixed fee amount required to be sent as value with each `createRaffle` operation.
        /// @dev `creationFee` is denominated in the smallest unit of the token. It must be sent as the transaction
        /// value during the execution of the payable `createRaffle` function.
        uint64 creationFee;
        /// @notice The transfer fee expressed in ether, where 0.01 ether corresponds to a 1% fee.
        /// @dev `poolFeePercentage` is not in basis points but in ether units, with each ether unit representing a
        /// percentage that will be collected from the pool on success draws.
        uint64 poolFeePercentage;
    }

    /// @dev Stores global fee data upcoming change and timestamp for that change.
    struct UpcomingFeeData {
        /// @notice The new fee value in wei to be applied at `valueChangeAt`.
        uint64 nextValue;
        /// @notice Timestamp at which a new fee value becomes effective.
        uint64 valueChangeAt;
    }

    /// @dev Stores custom fee data, including its current state, upcoming changes, and the timestamps for those
    /// changes.
    struct CustomFeeData {
        /// @notice Indicates if the custom fee is currently enabled.
        bool isEnabled;
        /// @notice The current fee value in wei.
        uint64 value;
        /// @notice The new fee value in wei to be applied at `valueChangeAt`.
        uint64 nextValue;
        /// @notice Timestamp at which a new fee value becomes effective.
        uint64 valueChangeAt;
        /// @notice Indicates the future state of `isEnabled` after `statusChangeAt`.
        bool nextEnableState;
        /// @notice Timestamp at which the change to `isEnabled` becomes effective.
        uint64 statusChangeAt;
    }

    /// @notice Exposes the creation fee for new `Raffl`s deployments.
    /// @param raffle Address of the `Raffl`.
    /// @dev Enabled custom fees overrides the global creation fee.
    function creationFeeData(address raffle) external view returns (address feeCollector, uint64 creationFeeValue);

    /// @notice Exposes the fee that will be collected from the pool on success draws for `Raffl`s.
    /// @param raffle Address of the `Raffl`.
    /// @dev Enabled custom fees overrides the global transfer fee.
    function poolFeeData(address raffle) external view returns (address feeCollector, uint64 poolFeePercentage);
}
