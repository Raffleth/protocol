// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.33;

import { Raffl } from "../../../src/Raffl.sol";
import { IRaffl } from "../../../src/interfaces/IRaffl.sol";
import { Errors } from "../../../src/libraries/RafflErrors.sol";

import { Common } from "../../utils/Common.sol";

contract RafflFreeEntriesTest is Common {
    Raffl raffl;
    uint256 entryPrice;

    function setUp() public virtual {
        fundAndSetPrizes(raffleCreator);

        vm.prank(raffleCreator);
        raffl = Raffl(
            rafflFactory.createRaffle(
                address(0), 0, MIN_ENTRIES, block.timestamp + DEADLINE_FROM_NOW, prizes, tokenGates, extraRecipient
            )
        );
        entryPrice = raffl.entryPrice();
    }

    /// @dev should ignore the quantity passed when acquiring entries
    function test_IgnoresTheQuantityAndNotThrows() public {
        vm.prank(userA);
        raffl.buyEntries(666);
    }

    /// @dev should only allow users to own 1 entry
    function test_RevertIf_MaxUserEntriesReached() public {
        vm.startPrank(userA);
        raffl.buyEntries(1);

        vm.expectRevert(Errors.MaxUserEntriesReached.selector);
        raffl.buyEntries(1);
        vm.stopPrank();
    }

    /// @dev should emit `EntriesBought` event when buying entries with 1 quantity and 0 value
    function test_EmitEntriesBought() public {
        uint256 quantity = 666;

        vm.expectEmit(true, true, true, true, address(raffl));
        emit IRaffl.EntriesBought(userA, 1, 0);

        vm.prank(userA);
        raffl.buyEntries(quantity);
    }

    /// @dev should set the `entries` to 1 for the user and should not increase the `pool` state
    function test_IncresesPoolOnFreeEntryAcquire() public {
        uint256 initialPool = raffl.pool();
        uint256 initialEntries = raffl.totalEntries();

        vm.prank(userA);
        raffl.buyEntries(666);

        uint256 currentPool = raffl.pool();
        assertEq(currentPool - initialPool, 0);

        uint256 currentEntries = raffl.totalEntries();
        assertEq(currentEntries - initialEntries, 1);
    }

    /// @dev should set correctly the `entriesMap` and `userEntriesMap` when buying entries
    function test_SetFreeEntriesMapAndUserEntriesMap() public {
        uint256 lastEntry = raffl.totalEntries();

        vm.prank(userA);
        raffl.buyEntries(666);

        uint256 entryNumber = lastEntry;
        address entryOwner = raffl.ownerOf(entryNumber);
        assertEq(entryOwner, userA);

        uint256 userTotalEntries = raffl.balanceOf(userA);
        assertEq(userTotalEntries, 1);
    }
}
