// SPDX-License-Identifier: None
// Raffl Protocol (last updated v1.0.0) (abstracts/EntriesManager.sol)
pragma solidity ^0.8.27;

/**
 * @title EntriesManager
 * @notice Manager contract that handles the acquisition of `Raffl` entries.
 * @dev This is an extract of @cygaar_dev and @vectorized.eth [ERC721A](https://erc721a.org) contract in order to manage
 * efficient minting of entries.
 *
 * Assumptions:
 *
 * - An owner cannot mint more than 2**64 - 1 (type(uint64).max).
 * - The maximum entry ID cannot exceed 2**256 - 1 (type(uint256).max).
 */
abstract contract EntriesManager {
    // =============================================================
    //                            CUSTOM ERRORS
    // =============================================================

    /// @notice Cannot query the balance for the zero address.
    error BalanceQueryForZeroAddress();

    /// @notice The entry does not exist.
    error OwnerQueryForNonexistentEntry();

    // =============================================================
    //                           CONSTANTS
    // =============================================================

    /// @dev Mask of an entry in packed address data.
    uint256 private constant _BITMASK_ADDRESS_DATA_ENTRY = (1 << 64) - 1;

    /// @dev The bit position of `numberMinted` in packed address data.
    uint256 private constant _BITPOS_NUMBER_MINTED = 64;

    /// @dev The mask of the lower 160 bits for addresses.
    uint256 private constant _BITMASK_ADDRESS = (1 << 160) - 1;

    // =============================================================
    //                            STORAGE
    // =============================================================

    /// @dev The next entry ID to be minted.
    uint256 private _currentIndex;

    // Mapping from entry ID to ownership details
    // An empty struct value does not necessarily mean the entry is unowned.
    // See {_packedOwnershipOf} implementation for details.
    //
    // Bits Layout:
    // - [0..159]   `addr`
    mapping(uint256 => uint256) private _packedOwnerships;

    // Mapping owner address to address data.
    //
    // Bits Layout:
    // - [0..63]    `balance`
    mapping(address => uint256) private _packedAddressData;

    // =============================================================
    //                   READ OPERATIONS
    // =============================================================

    /// @dev Returns the total amount of entries minted in the contract.
    function totalEntries() public view virtual returns (uint256 result) {
        unchecked {
            result = _currentIndex;
        }
    }

    /// @dev Returns the number of entries in `owner`'s account.
    function balanceOf(address owner) public view virtual returns (uint256) {
        if (owner == address(0)) _revert(BalanceQueryForZeroAddress.selector);
        return _packedAddressData[owner] & _BITMASK_ADDRESS_DATA_ENTRY;
    }

    /**
     * @dev Returns the owner of the `entryId`.
     *
     * Requirements:
     *
     * - `entryId` must exist.
     */
    function ownerOf(uint256 entryId) public view virtual returns (address) {
        return address(uint160(_packedOwnershipOf(entryId)));
    }

    // =============================================================
    //                     PRIVATE HELPERS
    // =============================================================

    /// @dev Returns the packed ownership data of `entryId`.
    function _packedOwnershipOf(uint256 entryId) private view returns (uint256 packed) {
        packed = _packedOwnerships[entryId];

        // If the data at the starting slot does not exist, start the scan.
        if (packed == 0) {
            if (entryId >= _currentIndex) _revert(OwnerQueryForNonexistentEntry.selector);
            // Invariant:
            // There will always be an initialized ownership slot
            // (i.e. `ownership.addr != address(0)`)
            // before an unintialized ownership slot
            // (i.e. `ownership.addr == address(0)`)
            // Hence, `entryId` will not underflow.
            //
            // We can directly compare the packed value.
            // If the address is zero, packed will be zero.
            for (;;) {
                unchecked {
                    packed = _packedOwnerships[--entryId];
                }
                if (packed == 0) continue;

                return packed;
            }
        }
        // Otherwise, the data exists and we can skip the scan.
        return packed;
    }

    /// @dev Packs ownership data into a single uint256.
    function _packOwnershipData(address owner) private pure returns (uint256 result) {
        assembly {
            // Mask `owner` to the lower 160 bits, in case the upper bits somehow aren't clean.
            result := and(owner, _BITMASK_ADDRESS)
        }
    }

    // =============================================================
    //                        MINT OPERATIONS
    // =============================================================

    /**
     * @dev Mints `quantity` entries and transfers them to `to`.
     *
     * Requirements:
     *
     * - `to` cannot be the zero address.
     * - `quantity` must be greater than 0.
     */
    function _mint(address to, uint256 quantity) internal virtual {
        uint256 startEntryId = _currentIndex;

        // Overflows are incredibly unrealistic.
        // `balance` and `numberMinted` have a maximum limit of 2**64.
        // `entryId` has a maximum limit of 2**256.
        unchecked {
            // Update `address` to the owner.
            _packedOwnerships[startEntryId] = _packOwnershipData(to);

            // Directly add to the `balance` and `numberMinted`.
            _packedAddressData[to] += quantity * ((1 << _BITPOS_NUMBER_MINTED) | 1);

            _currentIndex = startEntryId + quantity;
        }
    }

    /// @dev For more efficient reverts.
    function _revert(bytes4 errorSelector) internal pure {
        assembly {
            mstore(0x00, errorSelector)
            revert(0x00, 0x04)
        }
    }
}
