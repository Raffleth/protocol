// SPDX-License-Identifier: None
// Raffl Contracts (last updated v1.0.0) (Raffl.sol)
pragma solidity ^0.8.25;

/**
 * @title IFeeManager
 * @dev Interface that describes the struct and accessor function for the data related to the collection of fees.
 */
interface IFeeManager {
    /**
     * @dev `feeCollector` is the address that will collect the fees of every transaction of `Raffl`s
     * @dev `feePercentage` is the percentage that will be collected from the pool on success draws.
     * @dev `feePenality` is the amount in native token that will be charged on failed draws.
     */
    struct FeeData {
        address feeCollector;
        uint64 feePercentage;
        uint256 feePenality;
    }

    /**
     * @notice Exposes the `FeeData` for `Raffl`s to consume.
     */
    function feeData() external view returns (FeeData memory);
}
