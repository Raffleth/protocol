// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.25;

import { Raffl } from "../../../src/Raffl.sol";
import { IRaffl } from "../../../src/interfaces/IRaffl.sol";
import { RafflErrors } from "../../../src/libraries/Errors.sol";

import { Common } from "../../utils/Common.sol";
import { ERC20Mock } from "../../mocks/ERC20Mock.sol";

contract RafflRefundWithERC20EntriesTest is Common {
    Raffl raffl;

    ERC20Mock entryAsset;

    function setUp() public virtual {
        fundAndSetPrizes(raffleCreator);

        // Create the raffle
        entryAsset = new ERC20Mock();

        vm.prank(raffleCreator);
        raffl = Raffl(
            rafflFactory.createRaffle(
                address(entryAsset),
                ENTRY_PRICE,
                MIN_ENTRIES,
                block.timestamp + DEADLINE_FROM_NOW,
                prizes,
                tokenGates,
                extraRecipient
            )
        );
    }

    function processRaffleWithoutCriteriaMet() internal {
        if (raffl.criteriaMet()) revert("Refunds available when criteria not met.");

        vm.warp(raffl.deadline());
        performUpkeepOnActiveRaffl(raffl);

        assertTrue(raffl.gameStatus() == IRaffl.GameStatus.FailedDraw);
    }

    /// @dev should let users refund entries on `FailedDraw` state
    function test_AllowRefundsOnFailedDraw() public {
        uint256 quantity = 5;
        assertLt(quantity, raffl.minEntries());

        makeUserBuyEntries(raffl, entryAsset, userA, quantity);

        processRaffleWithoutCriteriaMet();

        uint256 amountPaid = raffl.entryPrice() * quantity;
        uint256 startUserBalance = entryAsset.balanceOf(userA);

        vm.startPrank(userA);
        vm.expectEmit(true, true, true, true, address(raffl));
        emit Raffl.EntriesRefunded(userA, quantity, amountPaid);
        raffl.refundEntries(userA);
        vm.stopPrank();

        assertEq(entryAsset.balanceOf(userA) - startUserBalance, amountPaid);
    }

    /// @dev should not let users request entries refund twice
    function test_RevertIf_UserRequestRefundTwice() public {
        makeUserBuyEntries(raffl, entryAsset, userA, 1);
        processRaffleWithoutCriteriaMet();

        vm.prank(userA);
        raffl.refundEntries(userA);

        vm.prank(userA);
        vm.expectRevert(RafflErrors.UserWithoutEntries.selector);
        raffl.refundEntries(userA);
    }

    /// @dev should only refund to users that bought entries
    function test_RevertIf_UserWithoutEntriesRequestRefund() public {
        processRaffleWithoutCriteriaMet();

        vm.prank(externalUser);
        vm.expectRevert(RafflErrors.UserWithoutEntries.selector);
        raffl.refundEntries(externalUser);
    }
}
