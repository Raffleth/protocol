// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.25;

import { Raffl } from "../../../src/Raffl.sol";
import { IRaffl } from "../../../src/interfaces/IRaffl.sol";
import { Errors } from "../../../src/libraries/RafflErrors.sol";

import { Common } from "../../utils/Common.sol";

contract RafflRefundWithNativeEntriesTest is Common {
    Raffl raffl;

    function setUp() public virtual {
        fundAndSetPrizes(raffleCreator);

        // Create the raffle
        raffl = createNewRaffle(raffleCreator);
    }

    /// @dev set FailedDraw on upkeep deadline when criteria not met.
    function test_SetFailedDrawWhenCriteriaNotMet() public {
        // Buy just 1 entry
        makeUserBuyEntries(raffl, userA, 1);

        assertEq(raffl.totalEntries(), 1);
        assertLt(raffl.totalEntries(), raffl.minEntries());
        assertFalse(raffl.criteriaMet());

        // Move to deadline
        vm.warp(raffl.deadline());

        // Perform upkeep
        (address activeRaffle, uint256 activeRafflIdx,) = findActiveRaffle(raffl);
        bytes memory performData = abi.encode(activeRaffle, activeRafflIdx);

        // Expect DeadlineFailedCriteria emit event
        vm.expectEmit(true, true, true, true, address(raffl));
        emit IRaffl.DeadlineFailedCriteria(raffl.totalEntries(), raffl.minEntries());
        rafflFactory.performUpkeep(performData);

        assertTrue(raffl.upkeepPerformed());

        assertTrue(raffl.gameStatus() == IRaffl.GameStatus.FailedDraw);
    }

    /// @dev should let users refund entries on `FailedDraw` state
    function test_AllowRefundsOnFailedDraw() public {
        uint256 quantity = 5;
        assertLt(quantity, raffl.minEntries());

        makeUserBuyEntries(raffl, userA, quantity);

        processRaffleWithoutCriteriaMet(raffl);

        uint256 amountPaid = raffl.entryPrice() * quantity;
        uint256 startUserBalance = userA.balance;

        vm.startPrank(userA);
        vm.expectEmit(true, true, true, true, address(raffl));
        emit IRaffl.EntriesRefunded(userA, quantity, amountPaid);
        raffl.refundEntries(userA);
        vm.stopPrank();

        assertEq(userA.balance - startUserBalance, amountPaid);
    }

    /// @dev should not let users request entries refund twice
    function test_RevertIf_UserRequestRefundTwice() public {
        makeUserBuyEntries(raffl, userA, 1);
        processRaffleWithoutCriteriaMet(raffl);

        vm.prank(userA);
        raffl.refundEntries(userA);

        vm.prank(userA);
        vm.expectRevert(Errors.UserAlreadyRefunded.selector);
        raffl.refundEntries(userA);
    }

    /// @dev should only refund to users that bought entries
    function test_RevertIf_UserWithoutEntriesRequestRefund() public {
        processRaffleWithoutCriteriaMet(raffl);

        vm.prank(externalUser);
        vm.expectRevert(Errors.UserWithoutEntries.selector);
        raffl.refundEntries(externalUser);
    }

    /// @dev should let the raffle creator withdraw back the prizes on `FailedDraw` state
    function test_AllowRaffleCreatorWithdrawBackPrizes() public {
        processRaffleWithoutCriteriaMet(raffl);

        uint256 startERC20Creator = testERC20.balanceOf(raffleCreator);
        uint256 startERC721Creator = testERC721.balanceOf(raffleCreator);

        assertEq(testERC20.balanceOf(address(raffl)), ERC20_AMOUNT);
        assertEq(testERC721.balanceOf(address(raffl)), 1);
        assertEq(testERC721.ownerOf(ERC721_TOKEN_ID), address(raffl));

        vm.startPrank(raffleCreator);
        vm.expectEmit();
        emit IRaffl.PrizesRefunded();
        raffl.refundPrizes();
        vm.stopPrank();

        assertEq(testERC20.balanceOf(raffleCreator) - startERC20Creator, ERC20_AMOUNT);
        assertEq(testERC721.balanceOf(raffleCreator) - startERC721Creator, 1);
        assertEq(testERC721.ownerOf(ERC721_TOKEN_ID), raffleCreator);
    }

    /// @dev should not let the raffle creator withdraw twice the prizes
    function test_RevertIf_CreatorRequestRefundTwice() public {
        processRaffleWithoutCriteriaMet(raffl);

        vm.prank(raffleCreator);
        raffl.refundPrizes();

        vm.prank(raffleCreator);
        vm.expectRevert(Errors.PrizesAlreadyRefunded.selector);
        raffl.refundPrizes();
    }

    /// @dev should only let the raffle creator withdraw back the prizes
    function test_RevertIf_NonCreatorRequestRefund() public {
        processRaffleWithoutCriteriaMet(raffl);

        vm.prank(attacker);
        vm.expectRevert(Errors.OnlyCreatorAllowed.selector);
        raffl.refundPrizes();
    }
}
