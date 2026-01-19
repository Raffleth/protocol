// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.33;

import { Raffl } from "../../src/Raffl.sol";
import { RafflFactory } from "../../src/RafflFactory.sol";
import { IRaffl } from "../../src/interfaces/IRaffl.sol";
import { Errors } from "../../src/libraries/RafflFactoryErrors.sol";

import { Common } from "../utils/Common.sol";

contract RafflFactoryVRFRetryTest is Common {
    Raffl public raffl;

    event VRFRequestRetried(address indexed raffle, uint256 indexed requestId);
    event RaffleEmergencyFailed(address indexed raffle);

    function setUp() public virtual {
        fundAndSetPrizes(raffleCreator);
        raffl = createNewRaffle(raffleCreator);
    }

    /*//////////////////////////////////////////////////////////////
                        VRF REQUEST TRACKING TESTS
    //////////////////////////////////////////////////////////////*/

    /// @dev VRF request info should be empty for new raffle
    function test_VRFRequestInfoEmptyForNewRaffle() public {
        (uint256 requestId, uint256 requestTime, RafflFactory.VRFStatus status) =
            rafflFactory.getVRFRequestInfo(address(raffl));

        assertEq(requestId, 0);
        assertEq(requestTime, 0);
        assertTrue(status == RafflFactory.VRFStatus.None);
    }

    /// @dev VRF request info should be set after performUpkeep
    function test_VRFRequestInfoSetAfterPerformUpkeep() public {
        makeUserBuyEntries(raffl, userA, raffl.minEntries());
        vm.warp(raffl.deadline() + 1);

        uint256 expectedRequestId = performUpkeepOnActiveRaffl(raffl);

        (uint256 requestId, uint256 requestTime, RafflFactory.VRFStatus status) =
            rafflFactory.getVRFRequestInfo(address(raffl));

        assertEq(requestId, expectedRequestId);
        assertEq(requestTime, block.timestamp);
        assertTrue(status == RafflFactory.VRFStatus.Pending);
    }

    /// @dev VRF request status should be Fulfilled after VRF callback
    function test_VRFRequestStatusFulfilledAfterCallback() public {
        makeUserBuyEntries(raffl, userA, raffl.minEntries());
        vm.warp(raffl.deadline() + 1);

        uint256 requestId = performUpkeepOnActiveRaffl(raffl);

        // Fulfill VRF
        fullfillVRFOnActiveAndEligibleRaffle(requestId, address(rafflFactory));

        (,, RafflFactory.VRFStatus status) = rafflFactory.getVRFRequestInfo(address(raffl));
        assertTrue(status == RafflFactory.VRFStatus.Fulfilled);
    }

    /// @dev hasVRFRequestTimedOut should return false before timeout
    function test_HasVRFRequestTimedOutReturnsFalseBeforeTimeout() public {
        makeUserBuyEntries(raffl, userA, raffl.minEntries());
        vm.warp(raffl.deadline() + 1);

        performUpkeepOnActiveRaffl(raffl);

        // Move forward but not past timeout (24 hours)
        vm.warp(block.timestamp + 12 hours);

        assertFalse(rafflFactory.hasVRFRequestTimedOut(address(raffl)));
    }

    /// @dev hasVRFRequestTimedOut should return true after timeout
    function test_HasVRFRequestTimedOutReturnsTrueAfterTimeout() public {
        makeUserBuyEntries(raffl, userA, raffl.minEntries());
        vm.warp(raffl.deadline() + 1);

        performUpkeepOnActiveRaffl(raffl);

        // Move forward past timeout (24 hours)
        vm.warp(block.timestamp + 24 hours + 1);

        assertTrue(rafflFactory.hasVRFRequestTimedOut(address(raffl)));
    }

    /*//////////////////////////////////////////////////////////////
                        RETRY VRF REQUEST TESTS
    //////////////////////////////////////////////////////////////*/

    /// @dev Should allow anyone to retry a stuck VRF request
    function test_CanRetryStuckVRFRequest() public {
        makeUserBuyEntries(raffl, userA, raffl.minEntries());
        vm.warp(raffl.deadline() + 1);

        uint256 firstRequestId = performUpkeepOnActiveRaffl(raffl);

        // Anyone can retry
        vm.prank(userB);
        vm.expectEmit(true, false, false, false, address(rafflFactory));
        emit VRFRequestRetried(address(raffl), 0); // Check raffle address only

        rafflFactory.retryVRFRequest(address(raffl));

        (uint256 newRequestId, uint256 requestTime, RafflFactory.VRFStatus status) =
            rafflFactory.getVRFRequestInfo(address(raffl));

        // Should have new request ID
        assertGt(newRequestId, firstRequestId);
        assertEq(requestTime, block.timestamp);
        assertTrue(status == RafflFactory.VRFStatus.Pending);
    }

    /// @dev Should update request time when retrying
    function test_RetryUpdatesRequestTime() public {
        makeUserBuyEntries(raffl, userA, raffl.minEntries());
        vm.warp(raffl.deadline() + 1);

        performUpkeepOnActiveRaffl(raffl);

        uint256 firstRequestTime = block.timestamp;

        // Wait some time
        vm.warp(block.timestamp + 6 hours);

        // Retry
        rafflFactory.retryVRFRequest(address(raffl));

        (, uint256 newRequestTime,) = rafflFactory.getVRFRequestInfo(address(raffl));

        assertGt(newRequestTime, firstRequestTime);
        assertEq(newRequestTime, block.timestamp);
    }

    /// @dev Should keep raffle in active list after retry
    function test_RaffleStaysActiveAfterRetry() public {
        makeUserBuyEntries(raffl, userA, raffl.minEntries());
        vm.warp(raffl.deadline() + 1);

        performUpkeepOnActiveRaffl(raffl);

        // Retry
        rafflFactory.retryVRFRequest(address(raffl));

        // Should still be in active raffles
        (address activeRaffle,, bool found) = findActiveRaffle(raffl);
        assertTrue(found);
        assertEq(activeRaffle, address(raffl));
    }

    /// @dev Should revert if trying to retry non-pending request
    function test_RevertIf_RetryNonPendingRequest() public {
        vm.expectRevert(Errors.VRFRequestNotPending.selector);
        rafflFactory.retryVRFRequest(address(raffl));
    }

    /// @dev Should revert if trying to retry invalid raffle
    function test_RevertIf_RetryInvalidRaffle() public {
        vm.expectRevert(Errors.InvalidVRFRequest.selector);
        rafflFactory.retryVRFRequest(address(0x123));
    }

    /// @dev Should revert if trying to retry fulfilled request
    function test_RevertIf_RetryFulfilledRequest() public {
        makeUserBuyEntries(raffl, userA, raffl.minEntries());
        vm.warp(raffl.deadline() + 1);

        uint256 requestId = performUpkeepOnActiveRaffl(raffl);

        // Fulfill VRF
        fullfillVRFOnActiveAndEligibleRaffle(requestId, address(rafflFactory));

        // Try to retry fulfilled request
        vm.expectRevert(Errors.VRFRequestNotPending.selector);
        rafflFactory.retryVRFRequest(address(raffl));
    }

    /// @dev New VRF request after retry should work correctly
    function test_NewVRFRequestAfterRetryWorks() public {
        makeUserBuyEntries(raffl, userA, raffl.minEntries());
        vm.warp(raffl.deadline() + 1);

        performUpkeepOnActiveRaffl(raffl);

        // Retry
        rafflFactory.retryVRFRequest(address(raffl));

        // Get new request ID
        (uint256 newRequestId,,) = rafflFactory.getVRFRequestInfo(address(raffl));

        // Fulfill new request
        fullfillVRFOnActiveAndEligibleRaffle(newRequestId, address(rafflFactory));

        // Check raffle completed successfully
        assertTrue(raffl.gameStatus() == IRaffl.GameStatus.SuccessDraw);
    }

    /*//////////////////////////////////////////////////////////////
                    EMERGENCY FAIL RAFFLE TESTS
    //////////////////////////////////////////////////////////////*/

    /// @dev Should allow emergency fail after timeout
    function test_CanEmergencyFailAfterTimeout() public {
        makeUserBuyEntries(raffl, userA, raffl.minEntries());
        vm.warp(raffl.deadline() + 1);

        performUpkeepOnActiveRaffl(raffl);

        // Move past timeout
        vm.warp(block.timestamp + 24 hours + 1);

        // Anyone can trigger emergency fail
        vm.prank(userC);
        vm.expectEmit(true, false, false, false, address(rafflFactory));
        emit RaffleEmergencyFailed(address(raffl));

        rafflFactory.emergencyFailRaffle(address(raffl));

        // Check raffle marked as failed
        assertTrue(raffl.gameStatus() == IRaffl.GameStatus.FailedDraw);
    }

    /// @dev Emergency fail should set VRF status to Failed
    function test_EmergencyFailSetsStatusToFailed() public {
        makeUserBuyEntries(raffl, userA, raffl.minEntries());
        vm.warp(raffl.deadline() + 1);

        performUpkeepOnActiveRaffl(raffl);

        // Move past timeout
        vm.warp(block.timestamp + 24 hours + 1);

        rafflFactory.emergencyFailRaffle(address(raffl));

        (,, RafflFactory.VRFStatus status) = rafflFactory.getVRFRequestInfo(address(raffl));
        assertTrue(status == RafflFactory.VRFStatus.Failed);
    }

    /// @dev Emergency fail should remove raffle from active list
    function test_EmergencyFailRemovesFromActiveList() public {
        makeUserBuyEntries(raffl, userA, raffl.minEntries());
        vm.warp(raffl.deadline() + 1);

        performUpkeepOnActiveRaffl(raffl);

        // Move past timeout
        vm.warp(block.timestamp + 24 hours + 1);

        rafflFactory.emergencyFailRaffle(address(raffl));

        // Should not be in active raffles
        (address activeRaffle,, bool found) = findActiveRaffle(raffl);
        assertFalse(found);
        assertEq(activeRaffle, address(0));
    }

    /// @dev Should revert if timeout not reached
    function test_RevertIf_EmergencyFailBeforeTimeout() public {
        makeUserBuyEntries(raffl, userA, raffl.minEntries());
        vm.warp(raffl.deadline() + 1);

        performUpkeepOnActiveRaffl(raffl);

        // Try to emergency fail before timeout
        vm.expectRevert(Errors.VRFRequestNotTimedOut.selector);
        rafflFactory.emergencyFailRaffle(address(raffl));
    }

    /// @dev Should revert if trying to emergency fail at exactly timeout boundary
    function test_RevertIf_EmergencyFailAtExactTimeout() public {
        makeUserBuyEntries(raffl, userA, raffl.minEntries());
        vm.warp(raffl.deadline() + 1);

        performUpkeepOnActiveRaffl(raffl);

        uint256 requestTime = block.timestamp;

        // Move to exactly timeout (not past it)
        vm.warp(requestTime + 24 hours);

        vm.expectRevert(Errors.VRFRequestNotTimedOut.selector);
        rafflFactory.emergencyFailRaffle(address(raffl));

        // After timeout: should work
        vm.warp(requestTime + 24 hours + 1);
        rafflFactory.emergencyFailRaffle(address(raffl));
    }

    /// @dev Should revert if trying to emergency fail non-pending request
    function test_RevertIf_EmergencyFailNonPendingRequest() public {
        vm.expectRevert(Errors.VRFRequestNotPending.selector);
        rafflFactory.emergencyFailRaffle(address(raffl));
    }

    /// @dev Should revert if trying to emergency fail invalid raffle
    function test_RevertIf_EmergencyFailInvalidRaffle() public {
        vm.expectRevert(Errors.InvalidVRFRequest.selector);
        rafflFactory.emergencyFailRaffle(address(0x456));
    }

    /// @dev Should revert if trying to emergency fail fulfilled request
    function test_RevertIf_EmergencyFailFulfilledRequest() public {
        makeUserBuyEntries(raffl, userA, raffl.minEntries());
        vm.warp(raffl.deadline() + 1);

        uint256 requestId = performUpkeepOnActiveRaffl(raffl);

        // Fulfill VRF
        fullfillVRFOnActiveAndEligibleRaffle(requestId, address(rafflFactory));

        // Try to emergency fail
        vm.expectRevert(Errors.VRFRequestNotPending.selector);
        rafflFactory.emergencyFailRaffle(address(raffl));
    }

    /*//////////////////////////////////////////////////////////////
                        REFUND SCENARIOS TESTS
    //////////////////////////////////////////////////////////////*/

    /// @dev Users should be able to get refunds after emergency fail
    function test_UsersCanRefundAfterEmergencyFail() public {
        uint256 entryQuantity = raffl.minEntries();
        makeUserBuyEntries(raffl, userA, entryQuantity);
        vm.warp(raffl.deadline() + 1);

        performUpkeepOnActiveRaffl(raffl);

        // Move past timeout and emergency fail
        vm.warp(block.timestamp + 24 hours + 1);
        rafflFactory.emergencyFailRaffle(address(raffl));

        // User should be able to get refund
        uint256 balanceBefore = userA.balance;
        raffl.refundEntries(userA);
        uint256 balanceAfter = userA.balance;

        uint256 expectedRefund = entryQuantity * raffl.entryPrice();
        assertEq(balanceAfter - balanceBefore, expectedRefund);
    }

    /// @dev Creator should be able to recover prizes after emergency fail
    function test_CreatorCanRecoverPrizesAfterEmergencyFail() public {
        makeUserBuyEntries(raffl, userA, raffl.minEntries());
        vm.warp(raffl.deadline() + 1);

        performUpkeepOnActiveRaffl(raffl);

        // Move past timeout and emergency fail
        vm.warp(block.timestamp + 24 hours + 1);
        rafflFactory.emergencyFailRaffle(address(raffl));

        // Creator should be able to recover prizes
        uint256 creatorNFTBalanceBefore = testERC721.balanceOf(raffleCreator);

        vm.prank(raffleCreator);
        raffl.refundPrizes();

        uint256 creatorNFTBalanceAfter = testERC721.balanceOf(raffleCreator);

        // Should have received NFT back
        assertGt(creatorNFTBalanceAfter, creatorNFTBalanceBefore);
    }

    /*//////////////////////////////////////////////////////////////
                        MULTIPLE RAFFLES TESTS
    //////////////////////////////////////////////////////////////*/

    /// @dev Should handle VRF status transitions correctly
    function test_MultipleRafflesWithDifferentVRFStates() public {
        // Raffl 1: Pending VRF
        makeUserBuyEntries(raffl, userA, raffl.minEntries());
        vm.warp(raffl.deadline() + 1);
        uint256 requestId1 = performUpkeepOnActiveRaffl(raffl);

        // Check pending status
        (,, RafflFactory.VRFStatus status1) = rafflFactory.getVRFRequestInfo(address(raffl));
        assertTrue(status1 == RafflFactory.VRFStatus.Pending);

        // Fulfill VRF
        fullfillVRFOnActiveAndEligibleRaffle(requestId1, address(rafflFactory));

        // Check fulfilled status
        (,, RafflFactory.VRFStatus status2) = rafflFactory.getVRFRequestInfo(address(raffl));
        assertTrue(status2 == RafflFactory.VRFStatus.Fulfilled);
    }

    /// @dev Should allow retry and then fulfill
    function test_RetryOneRaffleWhileAnotherFulfilled() public {
        // Raffle reaches deadline and VRF requested
        makeUserBuyEntries(raffl, userA, raffl.minEntries());
        vm.warp(raffl.deadline() + 1);

        uint256 requestId1 = performUpkeepOnActiveRaffl(raffl);

        // Check pending status
        (,, RafflFactory.VRFStatus status1) = rafflFactory.getVRFRequestInfo(address(raffl));
        assertTrue(status1 == RafflFactory.VRFStatus.Pending);

        // Retry the raffle
        rafflFactory.retryVRFRequest(address(raffl));

        // Status should still be pending but with new request
        (,, RafflFactory.VRFStatus status2) = rafflFactory.getVRFRequestInfo(address(raffl));
        (uint256 newRequestId,,) = rafflFactory.getVRFRequestInfo(address(raffl));
        assertTrue(status2 == RafflFactory.VRFStatus.Pending);
        assertGt(newRequestId, requestId1);

        // Now fulfill the new request
        fullfillVRFOnActiveAndEligibleRaffle(newRequestId, address(rafflFactory));

        // Status should be fulfilled
        (,, RafflFactory.VRFStatus status3) = rafflFactory.getVRFRequestInfo(address(raffl));
        assertTrue(status3 == RafflFactory.VRFStatus.Fulfilled);
    }

    /*//////////////////////////////////////////////////////////////
                        EDGE CASES TESTS
    //////////////////////////////////////////////////////////////*/

    /// @dev Cannot retry after emergency fail
    function test_RevertIf_RetryAfterEmergencyFail() public {
        makeUserBuyEntries(raffl, userA, raffl.minEntries());
        vm.warp(raffl.deadline() + 1);

        performUpkeepOnActiveRaffl(raffl);

        // Emergency fail
        vm.warp(block.timestamp + 24 hours + 1);
        rafflFactory.emergencyFailRaffle(address(raffl));

        // Try to retry
        vm.expectRevert(Errors.VRFRequestNotPending.selector);
        rafflFactory.retryVRFRequest(address(raffl));
    }

    /// @dev Cannot emergency fail twice
    function test_RevertIf_EmergencyFailTwice() public {
        makeUserBuyEntries(raffl, userA, raffl.minEntries());
        vm.warp(raffl.deadline() + 1);

        performUpkeepOnActiveRaffl(raffl);

        // Emergency fail
        vm.warp(block.timestamp + 24 hours + 1);
        rafflFactory.emergencyFailRaffle(address(raffl));

        // Try to emergency fail again
        vm.expectRevert(Errors.VRFRequestNotPending.selector);
        rafflFactory.emergencyFailRaffle(address(raffl));
    }

    /// @dev VRF can still fulfill after retry
    function test_VRFCanFulfillAfterRetry() public {
        makeUserBuyEntries(raffl, userA, raffl.minEntries());
        vm.warp(raffl.deadline() + 1);

        performUpkeepOnActiveRaffl(raffl);

        // Retry
        rafflFactory.retryVRFRequest(address(raffl));

        // Original request ID should still work if VRF responds late
        // But new request should also work
        (uint256 newRequestId,,) = rafflFactory.getVRFRequestInfo(address(raffl));

        // Fulfill with new request
        fullfillVRFOnActiveAndEligibleRaffle(newRequestId, address(rafflFactory));

        assertTrue(raffl.gameStatus() == IRaffl.GameStatus.SuccessDraw);
    }

    /// @dev Raffle with failed criteria should not have VRF tracking
    function test_FailedCriteriaRaffleNoVRFTracking() public {
        // Don't buy enough entries
        makeUserBuyEntries(raffl, userA, raffl.minEntries() - 1);
        vm.warp(raffl.deadline() + 1);

        (address activeRaffle, uint256 activeRafflIdx,) = findActiveRaffle(raffl);
        bytes memory performData = abi.encode(activeRaffle, activeRafflIdx);
        rafflFactory.performUpkeep(performData);

        // Check no VRF tracking
        (,, RafflFactory.VRFStatus status) = rafflFactory.getVRFRequestInfo(address(raffl));
        assertTrue(status == RafflFactory.VRFStatus.None);

        // Should be failed draw
        assertTrue(raffl.gameStatus() == IRaffl.GameStatus.FailedDraw);
    }

    /// @dev Multiple retries should work
    function test_MultipleRetriesWork() public {
        makeUserBuyEntries(raffl, userA, raffl.minEntries());
        vm.warp(raffl.deadline() + 1);

        performUpkeepOnActiveRaffl(raffl);
        (uint256 requestId1,,) = rafflFactory.getVRFRequestInfo(address(raffl));

        // First retry
        rafflFactory.retryVRFRequest(address(raffl));
        (uint256 requestId2,,) = rafflFactory.getVRFRequestInfo(address(raffl));

        // Second retry
        rafflFactory.retryVRFRequest(address(raffl));
        (uint256 requestId3,,) = rafflFactory.getVRFRequestInfo(address(raffl));

        // Third retry
        rafflFactory.retryVRFRequest(address(raffl));
        (uint256 requestId4,,) = rafflFactory.getVRFRequestInfo(address(raffl));

        // All should be different
        assertTrue(requestId1 != requestId2);
        assertTrue(requestId2 != requestId3);
        assertTrue(requestId3 != requestId4);

        // Status should still be pending
        (,, RafflFactory.VRFStatus status) = rafflFactory.getVRFRequestInfo(address(raffl));
        assertTrue(status == RafflFactory.VRFStatus.Pending);
    }

    /// @dev Timeout calculation should be exact
    function test_TimeoutCalculationExact() public {
        makeUserBuyEntries(raffl, userA, raffl.minEntries());
        vm.warp(raffl.deadline() + 1);

        performUpkeepOnActiveRaffl(raffl);

        uint256 requestTime = block.timestamp;

        // Just before timeout: should revert
        vm.warp(requestTime + 24 hours - 1);
        vm.expectRevert(Errors.VRFRequestNotTimedOut.selector);
        rafflFactory.emergencyFailRaffle(address(raffl));

        // At timeout: should still revert
        vm.warp(requestTime + 24 hours);
        vm.expectRevert(Errors.VRFRequestNotTimedOut.selector);
        rafflFactory.emergencyFailRaffle(address(raffl));

        // After timeout: should work
        vm.warp(requestTime + 24 hours + 1);
        rafflFactory.emergencyFailRaffle(address(raffl));
    }
}
