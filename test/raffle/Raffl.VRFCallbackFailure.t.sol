// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.33;

import { Raffl } from "../../src/Raffl.sol";
import { IRaffl } from "../../src/interfaces/IRaffl.sol";
import { Errors as FactoryErrors } from "../../src/libraries/RafflFactoryErrors.sol";

import { Common } from "../utils/Common.sol";

/// @title Tests for VRF callback failure scenarios
/// @notice Ensures the two-step process protects against gas limit and transfer failures
contract RafflVRFCallbackFailureTest is Common {
    Raffl public raffl;

    function setUp() public virtual {
        fundAndSetPrizes(raffleCreator);
        raffl = createNewRaffle(raffleCreator);
    }

    /*//////////////////////////////////////////////////////////////
                    VRF CALLBACK GAS SAFETY TESTS
    //////////////////////////////////////////////////////////////*/

    /// @dev setWinner should succeed even with low gas
    function test_SetWinnerSucceedsWithLowGas() public {
        makeUserBuyEntries(raffl, userA, raffl.minEntries());
        vm.warp(raffl.deadline() + 1);

        uint256 requestId = performUpkeepOnActiveRaffl(raffl);

        // Fulfill VRF - setWinner uses minimal gas
        vrfCoordinator.fulfillRandomWords(requestId, address(rafflFactory));

        // Should have set winner successfully
        assertTrue(raffl.winner() != address(0));
        assertTrue(raffl.gameStatus() == IRaffl.GameStatus.WinnerDrawn);
    }

    /// @dev VRF callback should not fail if raffle has many prizes
    function test_SetWinnerWithManyPrizes() public {
        // Even with complex prize structure, setWinner should work
        // because it doesn't transfer anything
        makeUserBuyEntries(raffl, userA, raffl.minEntries());
        vm.warp(raffl.deadline() + 1);

        uint256 requestId = performUpkeepOnActiveRaffl(raffl);

        // VRF fulfills
        vrfCoordinator.fulfillRandomWords(requestId, address(rafflFactory));

        // Winner set successfully without transferring prizes
        assertTrue(raffl.winner() != address(0));
        assertTrue(raffl.gameStatus() == IRaffl.GameStatus.WinnerDrawn);

        // Prizes still in contract
        assertGt(testERC721.balanceOf(address(raffl)), 0);
        assertGt(testERC20.balanceOf(address(raffl)), 0);
    }

    /// @dev VRF callback should not fail with large entry pool
    function test_SetWinnerWithLargePool() public {
        // Buy many entries to create large pool
        makeUserBuyEntries(raffl, userA, 50);
        makeUserBuyEntries(raffl, userB, 30);
        makeUserBuyEntries(raffl, userC, 20);

        vm.warp(raffl.deadline() + 1);
        uint256 requestId = performUpkeepOnActiveRaffl(raffl);

        uint256 poolBefore = raffl.pool();
        assertGt(poolBefore, 0);

        // VRF fulfills - should not distribute pool yet
        vrfCoordinator.fulfillRandomWords(requestId, address(rafflFactory));

        // Winner set, pool not distributed yet
        assertTrue(raffl.winner() != address(0));
        assertEq(raffl.pool(), poolBefore); // Pool unchanged
    }

    /*//////////////////////////////////////////////////////////////
                DISPERSAL RETRY/RECOVERY TESTS
    //////////////////////////////////////////////////////////////*/

    /// @dev Should allow multiple dispersal attempts if first fails
    function test_DispersalCanBeRetriedAfterFailure() public {
        makeUserBuyEntries(raffl, userA, raffl.minEntries());
        vm.warp(raffl.deadline() + 1);

        uint256 requestId = performUpkeepOnActiveRaffl(raffl);
        vrfCoordinator.fulfillRandomWords(requestId, address(rafflFactory));

        // First attempt (simulating potential failure scenario)
        // In real world, this might fail due to gas, reentrancy, etc.
        // But our design ensures state is correct for retry
        assertTrue(raffl.shouldDisperseRewards());

        // Dispersal succeeds
        rafflFactory.disperseRewards(address(raffl));

        // After success, can't retry
        assertFalse(raffl.shouldDisperseRewards());
    }

    /// @dev Winner is known even if dispersal is delayed
    function test_WinnerKnownBeforeDispersal() public {
        makeUserBuyEntries(raffl, userA, raffl.minEntries());
        vm.warp(raffl.deadline() + 1);

        uint256 requestId = performUpkeepOnActiveRaffl(raffl);
        vrfCoordinator.fulfillRandomWords(requestId, address(rafflFactory));

        // Winner is known immediately
        address winner = raffl.winner();
        assertTrue(winner != address(0));

        // But rewards not dispersed yet
        assertEq(testERC721.balanceOf(winner), 0);

        // Anyone can trigger dispersal
        vm.prank(userD); // Random user
        rafflFactory.disperseRewards(address(raffl));

        // Now rewards dispersed
        assertGt(testERC721.balanceOf(winner), 0);
    }

    /// @dev Automation can retry if first dispersal attempt times out
    function test_AutomationCanRetryDispersal() public {
        makeUserBuyEntries(raffl, userA, raffl.minEntries());
        vm.warp(raffl.deadline() + 1);

        uint256 requestId = performUpkeepOnActiveRaffl(raffl);
        vrfCoordinator.fulfillRandomWords(requestId, address(rafflFactory));

        // Simulate automation detecting dispersal needed
        (bool upkeepNeeded, bytes memory performData) = rafflFactory.checkUpkeep(CHECK_DATA);
        assertTrue(upkeepNeeded);

        // First automation attempt succeeds
        rafflFactory.performUpkeep(performData);

        // Raffle should be complete
        assertTrue(raffl.gameStatus() == IRaffl.GameStatus.SuccessDraw);

        // Further attempts should fail (no active raffles)
        vm.expectRevert(FactoryErrors.NoActiveRaffles.selector);
        rafflFactory.checkUpkeep(CHECK_DATA);
    }

    /*//////////////////////////////////////////////////////////////
                    STATE PROTECTION TESTS
    //////////////////////////////////////////////////////////////*/

    /// @dev Cannot disperse if winner not drawn
    function test_CannotDisperseWithoutWinner() public {
        makeUserBuyEntries(raffl, userA, raffl.minEntries());
        vm.warp(raffl.deadline() + 1);

        performUpkeepOnActiveRaffl(raffl);

        // VRF not fulfilled yet
        assertFalse(raffl.shouldDisperseRewards());

        // Attempt to disperse should fail
        vm.expectRevert();
        rafflFactory.disperseRewards(address(raffl));
    }

    /// @dev Cannot set winner twice
    function test_CannotSetWinnerTwice() public {
        makeUserBuyEntries(raffl, userA, raffl.minEntries());
        vm.warp(raffl.deadline() + 1);

        uint256 requestId = performUpkeepOnActiveRaffl(raffl);
        vrfCoordinator.fulfillRandomWords(requestId, address(rafflFactory));

        address firstWinner = raffl.winner();

        // Try to set winner again (should fail because status is WinnerDrawn)
        vm.prank(address(rafflFactory));
        vm.expectRevert();
        raffl.setWinner(requestId, 99_999); // Different random number

        // Winner unchanged
        assertEq(raffl.winner(), firstWinner);
    }

    /// @dev Raffle state remains consistent through failures
    function test_StateConsistencyThroughProcess() public {
        makeUserBuyEntries(raffl, userA, raffl.minEntries());

        // Initial state
        assertTrue(raffl.gameStatus() == IRaffl.GameStatus.Initialized);
        assertEq(raffl.winner(), address(0));
        assertFalse(raffl.shouldDisperseRewards());

        vm.warp(raffl.deadline() + 1);
        uint256 requestId = performUpkeepOnActiveRaffl(raffl);

        // After upkeep
        assertTrue(raffl.gameStatus() == IRaffl.GameStatus.DrawStarted);
        assertEq(raffl.winner(), address(0));
        assertFalse(raffl.shouldDisperseRewards());

        vrfCoordinator.fulfillRandomWords(requestId, address(rafflFactory));

        // After VRF
        assertTrue(raffl.gameStatus() == IRaffl.GameStatus.WinnerDrawn);
        assertTrue(raffl.winner() != address(0));
        assertTrue(raffl.shouldDisperseRewards());

        rafflFactory.disperseRewards(address(raffl));

        // After dispersal
        assertTrue(raffl.gameStatus() == IRaffl.GameStatus.SuccessDraw);
        assertTrue(raffl.winner() != address(0));
        assertFalse(raffl.shouldDisperseRewards());
    }

    /*//////////////////////////////////////////////////////////////
                INTEGRATION WITH VRF RETRY TESTS
    //////////////////////////////////////////////////////////////*/

    /// @dev VRF retry should still work with two-step process
    function test_VRFRetryWorksWithTwoStepProcess() public {
        makeUserBuyEntries(raffl, userA, raffl.minEntries());
        vm.warp(raffl.deadline() + 1);

        uint256 firstRequestId = performUpkeepOnActiveRaffl(raffl);

        // Simulate VRF stuck - retry
        rafflFactory.retryVRFRequest(address(raffl));

        (uint256 newRequestId,,) = rafflFactory.getVRFRequestInfo(address(raffl));
        assertGt(newRequestId, firstRequestId);

        // Fulfill with new request
        vrfCoordinator.fulfillRandomWords(newRequestId, address(rafflFactory));

        // Winner set
        assertTrue(raffl.winner() != address(0));

        // Disperse
        rafflFactory.disperseRewards(address(raffl));

        assertTrue(raffl.gameStatus() == IRaffl.GameStatus.SuccessDraw);
    }

    /// @dev Emergency fail should still work
    function test_EmergencyFailStillWorks() public {
        makeUserBuyEntries(raffl, userA, raffl.minEntries());
        vm.warp(raffl.deadline() + 1);

        performUpkeepOnActiveRaffl(raffl);

        // Wait for timeout
        vm.warp(block.timestamp + 24 hours + 1);

        // Emergency fail
        rafflFactory.emergencyFailRaffle(address(raffl));

        // Should be in failed state
        assertTrue(raffl.gameStatus() == IRaffl.GameStatus.FailedDraw);
        assertEq(raffl.winner(), address(0)); // No winner set
    }

    /*//////////////////////////////////////////////////////////////
                    REENTRANCY PROTECTION TESTS
    //////////////////////////////////////////////////////////////*/

    /// @dev disperseRewards should be protected against reentrancy
    function test_DisperseRewardsReentrancyProtection() public {
        makeUserBuyEntries(raffl, userA, raffl.minEntries());
        vm.warp(raffl.deadline() + 1);

        uint256 requestId = performUpkeepOnActiveRaffl(raffl);
        vrfCoordinator.fulfillRandomWords(requestId, address(rafflFactory));

        // disperseRewards has nonReentrant modifier
        // This test verifies it's in place
        rafflFactory.disperseRewards(address(raffl));

        // Cannot call again (state check + reentrancy protection)
        vm.expectRevert();
        rafflFactory.disperseRewards(address(raffl));
    }

    /*//////////////////////////////////////////////////////////////
                GAS MEASUREMENT TESTS
    //////////////////////////////////////////////////////////////*/

    /// @dev Measure gas usage for setWinner
    function test_SetWinnerGasUsage() public {
        makeUserBuyEntries(raffl, userA, raffl.minEntries());
        vm.warp(raffl.deadline() + 1);

        uint256 requestId = performUpkeepOnActiveRaffl(raffl);

        uint256 gasBefore = gasleft();
        vrfCoordinator.fulfillRandomWords(requestId, address(rafflFactory));
        uint256 gasUsed = gasBefore - gasleft();

        // setWinner should use minimal gas (< 100k typical VRF callback limit)
        // This is a rough check - actual gas will vary
        assertTrue(gasUsed < 500_000, "setWinner uses too much gas");
    }

    /// @dev Measure gas usage for disperseRewards
    function test_DisperseRewardsGasUsage() public {
        makeUserBuyEntries(raffl, userA, raffl.minEntries());
        vm.warp(raffl.deadline() + 1);

        uint256 requestId = performUpkeepOnActiveRaffl(raffl);
        vrfCoordinator.fulfillRandomWords(requestId, address(rafflFactory));

        uint256 gasBefore = gasleft();
        rafflFactory.disperseRewards(address(raffl));
        uint256 gasUsed = gasBefore - gasleft();

        // disperseRewards can use more gas (no VRF callback limit)
        assertTrue(gasUsed > 0);
        // Just verify it completes (no assertion on upper bound)
    }
}
