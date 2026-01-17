// SPDX-License-Identifier: None
// Raffl Protocol (last updated v1.0.0) (libraries/TokenLib.sol)
pragma solidity ^0.8.33;

import { IERC20Minimal } from "../interfaces/IERC20Minimal.sol";

/// @title TokenLib
/// @dev Library the contains helper methods for retrieving balances and transfering ERC-20 and ERC-721
library TokenLib {
    /// @notice Thrown when balanceOf call fails
    error BalanceOfFailed();

    /// @notice Thrown when transfer call fails
    error TransferFailed();

    /// @notice Thrown when transferFrom call fails
    error TransferFromFailed();

    /// @notice Retrieves the balance of a specified token for a given user
    /// @dev This function calls the `balanceOf` function on the token contract using the provided selector and decodes
    /// the returned data to retrieve the balance
    /// @param token The address of the token contract
    /// @param user The address of the user to query
    /// @return The balance of tokens held by the user
    function balanceOf(address token, address user) internal view returns (uint256) {
        (bool success, bytes memory data) =
            token.staticcall(abi.encodeWithSelector(IERC20Minimal.balanceOf.selector, user));
        if (!success || data.length < 32) revert BalanceOfFailed();
        return abi.decode(data, (uint256));
    }

    /// @notice Safely transfers tokens from the calling contract to a recipient
    /// @dev Calls the `transfer` function on the specified token contract and checks for successful transfer
    /// @param token The contract address of the token which will be transferred
    /// @param to The recipient of the transfer
    /// @param value The amount of tokens to be transferred
    function safeTransfer(address token, address to, uint256 value) internal {
        // Encode the function signature and arguments for the `transfer` function
        (bool success, bytes memory data) =
            token.call(abi.encodeWithSelector(IERC20Minimal.transfer.selector, to, value));
        // Check if the `transfer` function call was successful and no error data was returned
        if (!success || (data.length != 0 && !abi.decode(data, (bool)))) revert TransferFailed();
    }

    /// @notice Safely transfers tokens from one address to another using the `transferFrom` function
    /// @dev Calls the `transferFrom` function on the specified token contract and checks for successful transfer
    /// @param token The contract address of the token which will be transferred
    /// @param from The source address from which tokens will be transferred
    /// @param to The recipient address to which tokens will be transferred
    /// @param value The amount of tokens to be transferred
    function safeTransferFrom(address token, address from, address to, uint256 value) internal {
        // Encode the function signature and arguments for the `transferFrom` function
        (bool success, bytes memory data) =
            token.call(abi.encodeWithSelector(IERC20Minimal.transferFrom.selector, from, to, value));
        // Check if the `transferFrom` function call was successful and no error data was returned
        if (!success || (data.length != 0 && !abi.decode(data, (bool)))) revert TransferFromFailed();
    }
}
