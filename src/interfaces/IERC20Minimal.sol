// SPDX-License-Identifier: None
// Raffl Protocol (last updated v1.0.0) (interfaces/IERC20Minimal.sol)
pragma solidity ^0.8.27;

/// @title IERC20Minimal
/// @notice Interface for the ERC20 token standard with minimal functionality
interface IERC20Minimal {
    /// @notice Returns the balance of a token for a specific account
    /// @param account The address of the account to query
    /// @return The balance of tokens held by the account
    function balanceOf(address account) external view returns (uint256);

    /// @notice Transfers a specified amount of tokens from the caller's account to a recipient's account
    /// @param recipient The address of the recipient
    /// @param amount The amount of tokens to transfer
    /// @return True if the transfer was successful, False otherwise
    function transfer(address recipient, uint256 amount) external returns (bool);

    /// @notice Transfers a specified amount of tokens from a sender's account to a recipient's account
    /// @param sender The address of the sender
    /// @param recipient The address of the recipient
    /// @param amount The amount of tokens to transfer
    /// @return True if the transfer was successful, False otherwise
    function transferFrom(address sender, address recipient, uint256 amount) external returns (bool);
}
