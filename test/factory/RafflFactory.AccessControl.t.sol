// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.33;

import { Raffl } from "../../src/Raffl.sol";
import { RafflFactory } from "../../src/RafflFactory.sol";
import { IRaffl } from "../../src/interfaces/IRaffl.sol";
import { IFactoryFeeManager } from "../../src/interfaces/IFactoryFeeManager.sol";
import { Errors } from "../../src/libraries/RafflFactoryErrors.sol";

import { Common } from "../utils/Common.sol";

contract RafflAccessControlTest is Common {
    Raffl raffl;

    function setUp() public virtual {
        fundAndSetPrizes(raffleCreator);
    }

    /*//////////////////////////////////////////////////////////////
                        OWNERSHIP TESTS
    //////////////////////////////////////////////////////////////*/

    /// @dev Should have correct initial owner
    function test_InitialOwner() public view {
        assertEq(rafflFactory.owner(), admin);
    }

    /// @dev Should allow owner to transfer ownership (two-step)
    function test_OwnerCanTransferOwnership() public {
        address newOwner = address(0x9999);

        vm.prank(admin);
        rafflFactory.transferOwnership(newOwner);

        // Ownership not transferred yet (pending) - still admin
        assertEq(rafflFactory.owner(), admin);

        // New owner accepts
        vm.prank(newOwner);
        rafflFactory.acceptOwnership();

        assertEq(rafflFactory.owner(), newOwner);
    }

    /// @dev Should revert when non-owner tries to transfer ownership
    function test_RevertIf_NonOwnerTransfersOwnership() public {
        vm.expectRevert();
        vm.prank(attacker);
        rafflFactory.transferOwnership(attacker);
    }

    /// @dev Should revert when non-pending owner tries to accept ownership
    function test_RevertIf_NonPendingOwnerAccepts() public {
        vm.prank(admin);
        rafflFactory.transferOwnership(userA);

        vm.expectRevert();
        vm.prank(attacker);
        rafflFactory.acceptOwnership();
    }

    /// @dev Should allow owner to cancel pending transfer by transferring again
    function test_OwnerCanCancelTransfer() public {
        vm.prank(admin);
        rafflFactory.transferOwnership(userA);

        // Cancel by transferring to someone else
        vm.prank(admin);
        rafflFactory.transferOwnership(userB);

        // userA can no longer accept
        vm.expectRevert();
        vm.prank(userA);
        rafflFactory.acceptOwnership();

        // userB can accept
        vm.prank(userB);
        rafflFactory.acceptOwnership();
        assertEq(rafflFactory.owner(), userB);
    }

    /*//////////////////////////////////////////////////////////////
                        FEE COLLECTOR TESTS
    //////////////////////////////////////////////////////////////*/

    /// @dev Should have correct initial fee collector
    function test_InitialFeeCollector() public {
        (address collector,) = rafflFactory.creationFeeData(userA);
        assertEq(collector, feeCollector);
    }

    /// @dev Should allow owner to set new fee collector
    function test_OwnerCanSetFeeCollector() public {
        address newCollector = address(0x8888);

        vm.prank(admin);
        rafflFactory.setFeeCollector(newCollector);

        (address collector,) = rafflFactory.creationFeeData(userA);
        assertEq(collector, newCollector);
    }

    /// @dev Should revert when non-owner tries to set fee collector
    function test_RevertIf_NonOwnerSetsFeeCollector() public {
        vm.expectRevert();
        vm.prank(attacker);
        rafflFactory.setFeeCollector(attacker);
    }

    /// @dev Should revert when setting fee collector to zero address
    function test_RevertIf_SetFeeCollectorToZero() public {
        vm.expectRevert(Errors.AddressCanNotBeZero.selector);
        vm.prank(admin);
        rafflFactory.setFeeCollector(address(0));
    }

    /// @dev Should emit event when fee collector changes
    function test_FeeCollectorChangeEmitsEvent() public {
        address newCollector = address(0x8888);

        vm.expectEmit(true, true, true, true);
        emit IFactoryFeeManager.FeeCollectorChange(newCollector);

        vm.prank(admin);
        rafflFactory.setFeeCollector(newCollector);
    }

    /*//////////////////////////////////////////////////////////////
                        FEE MANAGEMENT ACCESS CONTROL
    //////////////////////////////////////////////////////////////*/

    /// @dev Should allow fee collector to schedule global creation fee
    function test_FeeCollectorCanScheduleCreationFee() public {
        vm.prank(feeCollector);
        rafflFactory.scheduleGlobalCreationFee(0.1 ether);

        // Verify it was scheduled (will be active after delay)
        vm.warp(block.timestamp + 1 hours);
        (address user, uint64 creationFee) = rafflFactory.creationFeeData(userA);
        assertEq(creationFee, 0.1 ether);
    }

    /// @dev Should revert when non-fee collector schedules creation fee
    function test_RevertIf_NonFeeCollectorSchedulesCreationFee() public {
        vm.expectRevert();
        vm.prank(attacker);
        rafflFactory.scheduleGlobalCreationFee(0.1 ether);

        vm.expectRevert();
        vm.prank(admin); // Owner but not fee collector
        rafflFactory.scheduleGlobalCreationFee(0.1 ether);
    }

    /// @dev Should allow fee collector to schedule global pool fee
    function test_FeeCollectorCanSchedulePoolFee() public {
        vm.prank(feeCollector);
        rafflFactory.scheduleGlobalPoolFee(0.08 ether); // 8%

        vm.warp(block.timestamp + 1 hours);
        (address user, uint64 poolFee) = rafflFactory.poolFeeData(userA);
        assertEq(poolFee, 0.08 ether);
    }

    /// @dev Should revert when non-fee collector schedules pool fee
    function test_RevertIf_NonFeeCollectorSchedulesPoolFee() public {
        vm.expectRevert();
        vm.prank(attacker);
        rafflFactory.scheduleGlobalPoolFee(0.08 ether);
    }

    /// @dev Should allow fee collector to schedule custom fees
    function test_FeeCollectorCanScheduleCustomFees() public {
        vm.startPrank(feeCollector);

        // Custom creation fee
        rafflFactory.scheduleCustomCreationFee(userA, 0.05 ether);
        rafflFactory.toggleCustomCreationFee(userA, true);

        // Custom pool fee
        rafflFactory.scheduleCustomPoolFee(userA, 0.02 ether);
        rafflFactory.toggleCustomPoolFee(userA, true);

        vm.stopPrank();

        vm.warp(block.timestamp + 1 hours);

        // Verify custom fees are active
        (address collector, uint64 creationFee) = rafflFactory.creationFeeData(userA);
        assertEq(creationFee, 0.05 ether);

        (, uint64 poolFee) = rafflFactory.poolFeeData(userA);
        assertEq(poolFee, 0.02 ether);
    }

    /// @dev Should revert when non-fee collector schedules custom fees
    function test_RevertIf_NonFeeCollectorSchedulesCustomFees() public {
        vm.expectRevert();
        vm.prank(attacker);
        rafflFactory.scheduleCustomCreationFee(userA, 0.05 ether);

        vm.expectRevert();
        vm.prank(attacker);
        rafflFactory.scheduleCustomPoolFee(userA, 0.02 ether);

        vm.expectRevert();
        vm.prank(attacker);
        rafflFactory.toggleCustomCreationFee(userA, true);

        vm.expectRevert();
        vm.prank(attacker);
        rafflFactory.toggleCustomPoolFee(userA, true);
    }

    /*//////////////////////////////////////////////////////////////
                        VRF SUBSCRIPTION ACCESS CONTROL
    //////////////////////////////////////////////////////////////*/

    /// @dev Should allow owner to handle subscription
    function test_OwnerCanHandleSubscription() public {
        vm.prank(admin);
        rafflFactory.handleSubscription(
            123, // subscriptionId
            bytes32(uint256(456)), // keyHash
            200_000, // callbackGasLimit
            5, // requestConfirmations
            false // nativePayment
        );

        assertEq(rafflFactory.subscriptionId(), 123);
    }

    /// @dev Should revert when non-owner handles subscription
    function test_RevertIf_NonOwnerHandlesSubscription() public {
        vm.expectRevert();
        vm.prank(feeCollector);
        rafflFactory.handleSubscription(123, bytes32(0), 200_000, 5, false);

        vm.expectRevert();
        vm.prank(attacker);
        rafflFactory.handleSubscription(123, bytes32(0), 200_000, 5, false);
    }

    /*//////////////////////////////////////////////////////////////
                        RAFFLE-LEVEL ACCESS CONTROL
    //////////////////////////////////////////////////////////////*/

    /// @dev Should only allow factory to call setSuccessCriteria
    function test_OnlyFactoryCanSetSuccessCriteria() public {
        raffl = createNewRaffle(raffleCreator);

        // Non-factory calls should fail
        vm.expectRevert();
        vm.prank(admin);
        raffl.setSuccessCriteria(123);

        vm.expectRevert();
        vm.prank(raffleCreator);
        raffl.setSuccessCriteria(123);

        vm.expectRevert();
        vm.prank(attacker);
        raffl.setSuccessCriteria(123);
    }

    /// @dev Should only allow factory to call setFailedCriteria
    function test_OnlyFactoryCanSetFailedCriteria() public {
        raffl = createNewRaffle(raffleCreator);

        vm.expectRevert();
        vm.prank(admin);
        raffl.setFailedCriteria();

        vm.expectRevert();
        vm.prank(raffleCreator);
        raffl.setFailedCriteria();

        vm.expectRevert();
        vm.prank(attacker);
        raffl.setFailedCriteria();
    }

    /// @dev Should only allow factory to call setWinner
    function test_OnlyFactoryCanSetWinner() public {
        raffl = createNewRaffle(raffleCreator);
        makeUserBuyEntries(raffl, userA, MIN_ENTRIES);

        vm.warp(raffl.deadline());
        performUpkeepOnActiveRaffl(raffl);

        vm.expectRevert();
        vm.prank(admin);
        raffl.setWinner(123, 456);

        vm.expectRevert();
        vm.prank(raffleCreator);
        raffl.setWinner(123, 456);

        vm.expectRevert();
        vm.prank(attacker);
        raffl.setWinner(123, 456);
    }

    /// @dev Should only allow creator to call refundPrizes
    function test_OnlyCreatorCanRefundPrizes() public {
        raffl = createNewRaffle(raffleCreator);
        makeUserBuyEntries(raffl, userA, 1);

        vm.warp(raffl.deadline());
        performUpkeepOnActiveRaffl(raffl);

        vm.expectRevert();
        vm.prank(admin);
        raffl.refundPrizes();

        vm.expectRevert();
        vm.prank(userA);
        raffl.refundPrizes();

        vm.expectRevert();
        vm.prank(attacker);
        raffl.refundPrizes();

        // Creator can refund
        vm.prank(raffleCreator);
        raffl.refundPrizes();
    }

    /*//////////////////////////////////////////////////////////////
                        PERMISSIONLESS FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /// @dev Should allow anyone to buy entries
    function test_AnyoneCanBuyEntries() public {
        raffl = createNewRaffle(raffleCreator);

        // Various users can buy
        makeUserBuyEntries(raffl, userA, 1);
        makeUserBuyEntries(raffl, userB, 1);
        makeUserBuyEntries(raffl, attacker, 1);
        makeUserBuyEntries(raffl, admin, 1);
        makeUserBuyEntries(raffl, feeCollector, 1);

        assertEq(raffl.totalEntries(), 5);
    }

    /// @dev Should allow anyone to refund entries (for any user)
    function test_AnyoneCanRefundEntries() public {
        raffl = createNewRaffle(raffleCreator);
        makeUserBuyEntries(raffl, userA, 5);

        vm.warp(raffl.deadline());
        performUpkeepOnActiveRaffl(raffl);

        // Anyone can trigger refund for userA
        vm.prank(attacker);
        raffl.refundEntries(userA);

        assertTrue(raffl.userRefund(userA));
    }

    /// @dev Should allow anyone to disperse rewards
    function test_AnyoneCanDisperseRewards() public {
        raffl = createNewRaffle(raffleCreator);
        makeUserBuyEntries(raffl, userA, MIN_ENTRIES);

        vm.warp(raffl.deadline());
        uint256 requestId = performUpkeepOnActiveRaffl(raffl);
        vrfCoordinator.fulfillRandomWords(requestId, address(rafflFactory));

        // Anyone can disperse
        vm.prank(attacker);
        raffl.disperseRewards();

        assertEq(uint8(raffl.gameStatus()), uint8(IRaffl.GameStatus.SuccessDraw));
    }

    /// @dev Should allow anyone to retry VRF request
    function test_AnyoneCanRetryVRF() public {
        raffl = createNewRaffle(raffleCreator);
        makeUserBuyEntries(raffl, userA, MIN_ENTRIES);

        vm.warp(raffl.deadline());
        performUpkeepOnActiveRaffl(raffl);

        // Anyone can retry
        vm.prank(attacker);
        rafflFactory.retryVRFRequest(address(raffl));

        // Verify retry happened (request info updated)
        (, uint256 requestTime,) = rafflFactory.getVRFRequestInfo(address(raffl));
        assertEq(requestTime, block.timestamp);
    }

    /// @dev Should allow anyone to emergency fail raffle (after timeout)
    function test_AnyoneCanEmergencyFail() public {
        raffl = createNewRaffle(raffleCreator);
        makeUserBuyEntries(raffl, userA, MIN_ENTRIES);

        vm.warp(raffl.deadline());
        performUpkeepOnActiveRaffl(raffl);

        // Wait for timeout
        vm.warp(block.timestamp + rafflFactory.VRF_REQUEST_TIMEOUT() + 1);

        // Anyone can emergency fail
        vm.prank(attacker);
        rafflFactory.emergencyFailRaffle(address(raffl));

        assertEq(uint8(raffl.gameStatus()), uint8(IRaffl.GameStatus.FailedDraw));
    }

    /// @dev Should allow anyone to call disperseRewards via factory
    function test_AnyoneCanDisperseRewardsViaFactory() public {
        raffl = createNewRaffle(raffleCreator);
        makeUserBuyEntries(raffl, userA, MIN_ENTRIES);

        vm.warp(raffl.deadline());
        uint256 requestId = performUpkeepOnActiveRaffl(raffl);
        vrfCoordinator.fulfillRandomWords(requestId, address(rafflFactory));

        // Anyone can disperse via factory
        vm.prank(attacker);
        rafflFactory.disperseRewards(address(raffl));

        assertEq(uint8(raffl.gameStatus()), uint8(IRaffl.GameStatus.SuccessDraw));
    }

    /*//////////////////////////////////////////////////////////////
                        ROLE SEPARATION TESTS
    //////////////////////////////////////////////////////////////*/

    /// @dev Should maintain separation between owner and fee collector roles
    function test_RoleSeparation() public {
        // Owner can set fee collector but not manage fees directly
        vm.prank(admin);
        rafflFactory.setFeeCollector(userA);

        // Old fee collector can no longer manage fees
        vm.expectRevert();
        vm.prank(feeCollector);
        rafflFactory.scheduleGlobalPoolFee(0.05 ether);

        // New fee collector can manage fees
        vm.prank(userA);
        rafflFactory.scheduleGlobalPoolFee(0.05 ether);

        // Owner still cannot manage fees directly
        vm.expectRevert();
        vm.prank(admin);
        rafflFactory.scheduleGlobalPoolFee(0.06 ether);
    }

    /// @dev Should allow fee collector to also be owner
    function test_FeeCollectorCanBeOwner() public {
        // Set owner as fee collector
        vm.prank(admin);
        rafflFactory.setFeeCollector(admin);

        // Admin can now do both owner and fee collector actions
        vm.startPrank(admin);
        rafflFactory.handleSubscription(999, bytes32(0), 100_000, 3, true);
        rafflFactory.scheduleGlobalPoolFee(0.07 ether);
        vm.stopPrank();

        assertEq(rafflFactory.subscriptionId(), 999);
    }
}
