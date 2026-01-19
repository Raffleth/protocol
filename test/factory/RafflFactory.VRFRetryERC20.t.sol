// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.33;

import { Raffl } from "../../src/Raffl.sol";
import { IRaffl } from "../../src/interfaces/IRaffl.sol";

import { Common } from "../utils/Common.sol";

contract RafflFactoryVRFRetryERC20Test is Common {
    Raffl public raffl;

    function setUp() public virtual {
        fundAndSetPrizes(raffleCreator);

        // Create raffle with ERC20 entries
        vm.prank(raffleCreator);
        raffl = Raffl(
            rafflFactory.createRaffle(
                address(testERC20),
                ENTRY_PRICE,
                MIN_ENTRIES,
                block.timestamp + DEADLINE_FROM_NOW,
                prizes,
                tokenGates,
                extraRecipient
            )
        );
    }

    /*//////////////////////////////////////////////////////////////
                    ERC20 SPECIFIC REFUND TESTS
    //////////////////////////////////////////////////////////////*/

    /// @dev Users should be able to get ERC20 refunds after emergency fail
    function test_UsersCanGetERC20RefundAfterEmergencyFail() public {
        uint256 entryQuantity = raffl.minEntries();

        // Fund users with ERC20
        testERC20.mint(userA, entryQuantity * raffl.entryPrice());

        // Approve and buy entries
        vm.startPrank(userA);
        testERC20.approve(address(raffl), entryQuantity * raffl.entryPrice());
        raffl.buyEntries(entryQuantity);
        vm.stopPrank();

        vm.warp(raffl.deadline() + 1);
        performUpkeepOnActiveRaffl(raffl);

        // Move past timeout and emergency fail
        vm.warp(block.timestamp + 24 hours + 1);
        rafflFactory.emergencyFailRaffle(address(raffl));

        // User should be able to get ERC20 refund
        uint256 balanceBefore = testERC20.balanceOf(userA);
        raffl.refundEntries(userA);
        uint256 balanceAfter = testERC20.balanceOf(userA);

        uint256 expectedRefund = entryQuantity * raffl.entryPrice();
        assertEq(balanceAfter - balanceBefore, expectedRefund);
    }

    /// @dev Multiple users should be able to get ERC20 refunds
    function test_MultipleUsersCanGetERC20Refunds() public {
        uint256 userAEntries = 5;
        uint256 userBEntries = 3;
        uint256 userCEntries = 2;

        // Fund and buy entries for userA
        testERC20.mint(userA, userAEntries * raffl.entryPrice());
        vm.startPrank(userA);
        testERC20.approve(address(raffl), userAEntries * raffl.entryPrice());
        raffl.buyEntries(userAEntries);
        vm.stopPrank();

        // Fund and buy entries for userB
        testERC20.mint(userB, userBEntries * raffl.entryPrice());
        vm.startPrank(userB);
        testERC20.approve(address(raffl), userBEntries * raffl.entryPrice());
        raffl.buyEntries(userBEntries);
        vm.stopPrank();

        // Fund and buy entries for userC
        testERC20.mint(userC, userCEntries * raffl.entryPrice());
        vm.startPrank(userC);
        testERC20.approve(address(raffl), userCEntries * raffl.entryPrice());
        raffl.buyEntries(userCEntries);
        vm.stopPrank();

        vm.warp(raffl.deadline() + 1);
        performUpkeepOnActiveRaffl(raffl);

        // Emergency fail
        vm.warp(block.timestamp + 24 hours + 1);
        rafflFactory.emergencyFailRaffle(address(raffl));

        // All users get refunds
        uint256 balanceABefore = testERC20.balanceOf(userA);
        raffl.refundEntries(userA);
        assertEq(testERC20.balanceOf(userA) - balanceABefore, userAEntries * raffl.entryPrice());

        uint256 balanceBBefore = testERC20.balanceOf(userB);
        raffl.refundEntries(userB);
        assertEq(testERC20.balanceOf(userB) - balanceBBefore, userBEntries * raffl.entryPrice());

        uint256 balanceCBefore = testERC20.balanceOf(userC);
        raffl.refundEntries(userC);
        assertEq(testERC20.balanceOf(userC) - balanceCBefore, userCEntries * raffl.entryPrice());
    }

    /// @dev Retry should work with ERC20 raffles
    function test_RetryWorksWithERC20Raffle() public {
        testERC20.mint(userA, raffl.minEntries() * raffl.entryPrice());

        vm.startPrank(userA);
        testERC20.approve(address(raffl), raffl.minEntries() * raffl.entryPrice());
        raffl.buyEntries(raffl.minEntries());
        vm.stopPrank();

        vm.warp(raffl.deadline() + 1);
        uint256 firstRequestId = performUpkeepOnActiveRaffl(raffl);

        // Retry
        rafflFactory.retryVRFRequest(address(raffl));

        (uint256 newRequestId,,) = rafflFactory.getVRFRequestInfo(address(raffl));
        assertGt(newRequestId, firstRequestId);

        // Fulfill and verify success
        fullfillVRFOnActiveAndEligibleRaffle(newRequestId, address(rafflFactory));
        assertTrue(raffl.gameStatus() == IRaffl.GameStatus.SuccessDraw);
    }

    /// @dev Pool should be transferred correctly after retry and fulfill
    function test_PoolTransferredCorrectlyAfterRetry() public {
        uint256 entries = raffl.minEntries();
        testERC20.mint(userA, entries * raffl.entryPrice());

        vm.startPrank(userA);
        testERC20.approve(address(raffl), entries * raffl.entryPrice());
        raffl.buyEntries(entries);
        vm.stopPrank();

        vm.warp(raffl.deadline() + 1);
        performUpkeepOnActiveRaffl(raffl);

        // Retry
        rafflFactory.retryVRFRequest(address(raffl));
        (uint256 newRequestId,,) = rafflFactory.getVRFRequestInfo(address(raffl));

        // Record creator balance before
        uint256 creatorBalanceBefore = testERC20.balanceOf(raffleCreator);

        // Fulfill
        fullfillVRFOnActiveAndEligibleRaffle(newRequestId, address(rafflFactory));

        // Creator should have received pool funds
        uint256 creatorBalanceAfter = testERC20.balanceOf(raffleCreator);
        assertGt(creatorBalanceAfter, creatorBalanceBefore);
    }
}
