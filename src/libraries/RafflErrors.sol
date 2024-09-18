// SPDX-License-Identifier: None
// Raffl Protocol (last updated v1.0.0) (libraries/RafflErrors.sol)
pragma solidity ^0.8.27;

/// @title Errors Library for Raffl.sol
library Errors {
    /// @notice Thrown if anyone other than the factory tries to interact.
    error OnlyFactoryAllowed();

    /// @notice Thrown if anyone other than the creator tries to interact.
    error OnlyCreatorAllowed();

    /// @notice Thrown if no entry quantity is provided.
    error EntryQuantityRequired();

    /// @notice Thrown if the entries purchase period is closed.
    error EntriesPurchaseClosed();

    /// @notice Thrown if invalid value provided for entries purchase.
    error EntriesPurchaseInvalidValue();

    /// @notice Thrown if refunds are initiated before draw failure.
    error RefundsOnlyAllowedOnFailedDraw();

    /// @notice Thrown if a user without entries tries to claim.
    error UserWithoutEntries();

    /// @notice Thrown if a user was already refunded entries.
    error UserAlreadyRefunded();

    /// @notice Thrown if prizes are already refunded.
    error PrizesAlreadyRefunded();

    /// @notice Thrown if the maximum entries limit per user has been reached.
    error MaxUserEntriesReached();

    /// @notice Thrown if the total maximum entries limit has been reached.
    error MaxTotalEntriesReached();

    /// @notice Thrown if the refund operation is initiated without any refunds.
    error WithoutRefunds();

    /// @notice Thrown if token gate restriction is violated.
    error TokenGateRestriction();
}
