// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.25;

import { Raffl } from "../../../src/Raffl.sol";
import { IRaffl } from "../../../src/interfaces/IRaffl.sol";
import { RafflErrors } from "../../../src/libraries/Errors.sol";

import { Common } from "../../utils/Common.sol";

contract RafflRefundWithFreeEntriesTest is Common {
    Raffl raffl;

    function setUp() public virtual {
        fundAndSetPrizes(raffleCreator);

        // Create the raffle
        vm.prank(raffleCreator);
        ENTRY_PRICE = 0;
        raffl = Raffl(
            rafflFactory.createRaffle(
                address(0),
                ENTRY_PRICE,
                MIN_ENTRIES,
                block.timestamp + DEADLINE_FROM_NOW,
                prizes,
                tokenGates,
                extraRecipient
            )
        );
    }

    /// @dev should not let users refund free entries on `FailedDraw` state
    function test_RevertIf_UserRequestRefundOnFreeEntries() public {
        uint256 quantity = 5;
        assertLt(quantity, raffl.minEntries());

        makeUserBuyEntries(raffl, userA, quantity);

        processRaffleWithoutCriteriaMet(raffl);

        assertEq(address(raffl).balance, 0);

        vm.startPrank(userA);
        vm.expectRevert(RafflErrors.WithoutRefunds.selector);
        raffl.refundEntries(userA);
        vm.stopPrank();

        assertEq(address(raffl).balance, 0);
    }
}
