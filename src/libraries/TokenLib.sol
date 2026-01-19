// SPDX-License-Identifier: None
// Raffl Protocol (last updated v2.0.0) (libraries/TokenLib.sol)
pragma solidity ^0.8.33;

/// @title TokenLib
/// @dev Gas-optimized library for ERC-20 and ERC-721 balance checks and transfers using inline assembly.
/// @dev Saves ~200-600 gas per call compared to high-level Solidity implementations.
library TokenLib {
    /// @notice Thrown when balanceOf call fails
    error BalanceOfFailed();

    /// @notice Thrown when transfer call fails
    error TransferFailed();

    /// @notice Thrown when transferFrom call fails
    error TransferFromFailed();

    /// @dev Selectors for ERC20 functions (computed at compile time)
    bytes4 private constant BALANCE_OF_SELECTOR = 0x70a08231; // balanceOf(address)
    bytes4 private constant TRANSFER_SELECTOR = 0xa9059cbb; // transfer(address,uint256)
    bytes4 private constant TRANSFER_FROM_SELECTOR = 0x23b872dd; // transferFrom(address,address,uint256)

    /// @notice Retrieves the balance of a specified token for a given user
    /// @dev Uses inline assembly for gas optimization (~200-500 gas savings)
    /// @param token The address of the token contract
    /// @param user The address of the user to query
    /// @return result The balance of tokens held by the user
    function balanceOf(address token, address user) internal view returns (uint256 result) {
        /// @solidity memory-safe-assembly
        assembly {
            // Get free memory pointer
            let ptr := mload(0x40)

            // Store selector and user address
            // balanceOf(address) selector: 0x70a08231
            mstore(ptr, 0x70a0823100000000000000000000000000000000000000000000000000000000)
            mstore(add(ptr, 0x04), user)

            // Make the staticcall
            // staticcall(gas, address, argsOffset, argsSize, retOffset, retSize)
            let success := staticcall(gas(), token, ptr, 0x24, ptr, 0x20)

            // Check if call succeeded and returned data
            if iszero(and(success, gt(returndatasize(), 0x1f))) {
                // Store BalanceOfFailed() selector and revert
                mstore(0x00, 0x4963f6d5) // BalanceOfFailed()
                revert(0x1c, 0x04)
            }

            // Load and return the balance
            result := mload(ptr)
        }
    }

    /// @notice Safely transfers tokens from the calling contract to a recipient
    /// @dev Uses inline assembly for gas optimization (~300-600 gas savings)
    /// @dev Handles tokens that don't return a boolean (non-standard ERC20)
    /// @param token The contract address of the token which will be transferred
    /// @param to The recipient of the transfer
    /// @param value The amount of tokens to be transferred
    function safeTransfer(address token, address to, uint256 value) internal {
        /// @solidity memory-safe-assembly
        assembly {
            // Get free memory pointer
            let ptr := mload(0x40)

            // Store transfer(address,uint256) selector and arguments
            mstore(ptr, 0xa9059cbb00000000000000000000000000000000000000000000000000000000)
            mstore(add(ptr, 0x04), to)
            mstore(add(ptr, 0x24), value)

            // Make the call
            let success := call(gas(), token, 0, ptr, 0x44, ptr, 0x20)

            // Check success: call must succeed and either return nothing or return true
            // returndatasize == 0 || (returndatasize >= 32 && returned value != 0)
            let valid := or(iszero(returndatasize()), and(gt(returndatasize(), 0x1f), gt(mload(ptr), 0)))

            if iszero(and(success, valid)) {
                // Store TransferFailed() selector and revert
                mstore(0x00, 0x90b8ec18) // TransferFailed()
                revert(0x1c, 0x04)
            }
        }
    }

    /// @notice Safely transfers tokens from one address to another using the `transferFrom` function
    /// @dev Uses inline assembly for gas optimization (~300-600 gas savings)
    /// @dev Handles tokens that don't return a boolean (non-standard ERC20)
    /// @param token The contract address of the token which will be transferred
    /// @param from The source address from which tokens will be transferred
    /// @param to The recipient address to which tokens will be transferred
    /// @param value The amount of tokens to be transferred
    function safeTransferFrom(address token, address from, address to, uint256 value) internal {
        /// @solidity memory-safe-assembly
        assembly {
            // Get free memory pointer
            let ptr := mload(0x40)

            // Store transferFrom(address,address,uint256) selector and arguments
            mstore(ptr, 0x23b872dd00000000000000000000000000000000000000000000000000000000)
            mstore(add(ptr, 0x04), from)
            mstore(add(ptr, 0x24), to)
            mstore(add(ptr, 0x44), value)

            // Make the call
            let success := call(gas(), token, 0, ptr, 0x64, ptr, 0x20)

            // Check success: call must succeed and either return nothing or return true
            // returndatasize == 0 || (returndatasize >= 32 && returned value != 0)
            let valid := or(iszero(returndatasize()), and(gt(returndatasize(), 0x1f), gt(mload(ptr), 0)))

            if iszero(and(success, valid)) {
                // Store TransferFromFailed() selector and revert
                mstore(0x00, 0x7939f424) // TransferFromFailed()
                revert(0x1c, 0x04)
            }
        }
    }
}
