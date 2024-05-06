// SPDX-License-Identifier: None
// Raffl Protocol (last updated v1.0.0) (libraries/RafflFactoryErrors.sol)
pragma solidity ^0.8.25;

/// @title Errors Library for RafflFactory.sol
library Errors {
    /// @notice Thrown if the provided address is a zero address.
    error AddressCanNotBeZero();

    /// @notice Thrown if contract deployment fails.
    error FailedToDeploy();

    /// @notice Thrown if the fee does falls outside the allowed range.
    error FeeOutOfRange();

    /// @notice Thrown if the sender is not a fee collector.
    error NotFeeCollector();

    /// @notice Thrown if the provided deadline is not in the future.
    error DeadlineIsNotFuture();

    /// @notice Thrown if transfer from prize pool fails.
    error UnsuccessfulTransferFromPrize();

    /// @notice Thrown if the prize amount in ERC20 token is zero.
    error ERC20PrizeAmountIsZero();

    /// @notice Thrown if the upkeep condition is not met.
    error UpkeepConditionNotMet();

    /// @notice Thrown if there are no active raffles.
    error NoActiveRaffles();

    /// @notice Thrown if the lower and upper bounds of raffle are invalid.
    error InvalidLowerAndUpperBounds();

    /// @notice Thrown if the active raffle index is out of bounds.
    error ActiveRaffleIndexOutOfBounds();

    /// @notice Error to indicate that the creation fee is insufficient.
    error InsufficientCreationFee();

    /// @notice Error to indicate an unsuccessful transfer of the creation fee.
    error UnsuccessfulCreationFeeTransfer();
}
