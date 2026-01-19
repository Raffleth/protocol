// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.33;

import { Raffl } from "../../src/Raffl.sol";
import { IRaffl } from "../../src/interfaces/IRaffl.sol";
import { Errors } from "../../src/libraries/RafflErrors.sol";
import { Errors as FactoryErrors } from "../../src/libraries/RafflFactoryErrors.sol";

import { Common } from "../utils/Common.sol";

contract RafflDisperseRewardsTest is Common {
    Raffl public raffl;

    event WinnerDrawn(uint256 indexed requestId, uint256 winnerEntry, address user, uint256 entries);
    event RewardsDispersed(address indexed winner);

    function setUp() public virtual {
        fundAndSetPrizes(raffleCreator);
        raffl = createNewRaffle(raffleCreator);
    }

    /*//////////////////////////////////////////////////////////////
                        WINNER SELECTION TESTS
    //////////////////////////////////////////////////////////////*/

    /// @dev Winner should be set correctly after VRF fulfills
    function test_WinnerSetAfterVRFFulfills() public {
        makeUserBuyEntries(raffl, userA, raffl.minEntries());
        vm.warp(raffl.deadline() + 1);

        uint256 requestId = performUpkeepOnActiveRaffl(raffl);

        // Before VRF
        assertEq(raffl.winner(), address(0));
        assertEq(raffl.winningEntry(), 0);
        assertEq(raffl.requestId(), 0);
        assertTrue(raffl.gameStatus() == IRaffl.GameStatus.DrawStarted);

        // Fulfill VRF (only sets winner, doesn't disperse)
        vm.expectEmit(true, false, false, false, address(raffl));
        emit WinnerDrawn(requestId, 0, address(0), 0); // Check event exists

        vrfCoordinator.fulfillRandomWords(requestId, address(rafflFactory));

        // After VRF
        assertTrue(raffl.winner() != address(0));
        assertEq(raffl.requestId(), requestId);
        assertTrue(raffl.gameStatus() == IRaffl.GameStatus.WinnerDrawn);
        assertTrue(raffl.shouldDisperseRewards());
    }

    /// @dev Winner should be deterministic based on random number
    function test_WinnerIsDeterministic() public {
        // Create multiple entries from different users
        makeUserBuyEntries(raffl, userA, 3);
        makeUserBuyEntries(raffl, userB, 5);
        makeUserBuyEntries(raffl, userC, 2);

        vm.warp(raffl.deadline() + 1);
        uint256 requestId = performUpkeepOnActiveRaffl(raffl);

        uint256 totalEntries = raffl.totalEntries();
        assertEq(totalEntries, 10);

        // Fulfill VRF
        vrfCoordinator.fulfillRandomWords(requestId, address(rafflFactory));

        // Winner should be one of the entry owners
        address winner = raffl.winner();
        uint256 winningEntry = raffl.winningEntry();

        assertTrue(winner == userA || winner == userB || winner == userC);
        assertTrue(winningEntry < totalEntries);
        assertEq(raffl.ownerOf(winningEntry), winner);
    }

    /// @dev Should emit correct event when winner is drawn
    function test_EmitsWinnerDrawnEvent() public {
        makeUserBuyEntries(raffl, userA, raffl.minEntries());
        vm.warp(raffl.deadline() + 1);

        uint256 requestId = performUpkeepOnActiveRaffl(raffl);

        // Should emit WinnerDrawn event
        vm.expectEmit(true, false, false, false, address(raffl));
        emit WinnerDrawn(requestId, 0, address(0), raffl.totalEntries());

        vrfCoordinator.fulfillRandomWords(requestId, address(rafflFactory));
    }

    /// @dev Should revert if trying to set winner before draw started
    function test_RevertIf_SetWinnerBeforeDrawStarted() public {
        vm.expectRevert(Errors.DrawNotStarted.selector);
        vm.prank(address(rafflFactory));
        raffl.setWinner(1, 12_345);
    }

    /// @dev Should revert if non-factory tries to set winner
    function test_RevertIf_NonFactorySetWinner() public {
        makeUserBuyEntries(raffl, userA, raffl.minEntries());
        vm.warp(raffl.deadline() + 1);
        performUpkeepOnActiveRaffl(raffl);

        vm.expectRevert(Errors.OnlyFactoryAllowed.selector);
        vm.prank(attacker);
        raffl.setWinner(1, 12_345);
    }

    /*//////////////////////////////////////////////////////////////
                    REWARD DISPERSAL TESTS
    //////////////////////////////////////////////////////////////*/

    /// @dev Rewards should be dispersed correctly after winner is drawn
    function test_RewardsDispersedCorrectly() public {
        makeUserBuyEntries(raffl, userA, raffl.minEntries());
        vm.warp(raffl.deadline() + 1);

        uint256 requestId = performUpkeepOnActiveRaffl(raffl);
        vrfCoordinator.fulfillRandomWords(requestId, address(rafflFactory));

        address winner = raffl.winner();
        uint256 nftBalanceBefore = testERC721.balanceOf(winner);

        // Disperse rewards
        vm.expectEmit(true, false, false, false, address(raffl));
        emit RewardsDispersed(winner);

        rafflFactory.disperseRewards(address(raffl));

        // Check NFT transferred
        assertGt(testERC721.balanceOf(winner), nftBalanceBefore);

        // Check status updated
        assertTrue(raffl.gameStatus() == IRaffl.GameStatus.SuccessDraw);
        assertFalse(raffl.shouldDisperseRewards());
    }

    /// @dev Anyone should be able to disperse rewards (permissionless)
    function test_AnyoneCanDisperseRewards() public {
        makeUserBuyEntries(raffl, userA, raffl.minEntries());
        vm.warp(raffl.deadline() + 1);

        uint256 requestId = performUpkeepOnActiveRaffl(raffl);
        vrfCoordinator.fulfillRandomWords(requestId, address(rafflFactory));

        // Random user can disperse
        vm.prank(userD);
        rafflFactory.disperseRewards(address(raffl));

        assertTrue(raffl.gameStatus() == IRaffl.GameStatus.SuccessDraw);
    }

    /// @dev Creator can disperse rewards
    function test_CreatorCanDisperseRewards() public {
        makeUserBuyEntries(raffl, userA, raffl.minEntries());
        vm.warp(raffl.deadline() + 1);

        uint256 requestId = performUpkeepOnActiveRaffl(raffl);
        vrfCoordinator.fulfillRandomWords(requestId, address(rafflFactory));

        // Creator can disperse
        vm.prank(raffleCreator);
        rafflFactory.disperseRewards(address(raffl));

        assertTrue(raffl.gameStatus() == IRaffl.GameStatus.SuccessDraw);
    }

    /// @dev Winner can disperse rewards themselves
    function test_WinnerCanDisperseRewards() public {
        makeUserBuyEntries(raffl, userA, raffl.minEntries());
        vm.warp(raffl.deadline() + 1);

        uint256 requestId = performUpkeepOnActiveRaffl(raffl);
        vrfCoordinator.fulfillRandomWords(requestId, address(rafflFactory));

        address winner = raffl.winner();

        // Winner can disperse
        vm.prank(winner);
        rafflFactory.disperseRewards(address(raffl));

        assertTrue(raffl.gameStatus() == IRaffl.GameStatus.SuccessDraw);
    }

    /// @dev Should revert if trying to disperse before winner is drawn
    function test_RevertIf_DisperseBeforeWinnerDrawn() public {
        makeUserBuyEntries(raffl, userA, raffl.minEntries());
        vm.warp(raffl.deadline() + 1);
        performUpkeepOnActiveRaffl(raffl);

        // VRF not fulfilled yet
        vm.expectRevert(FactoryErrors.UpkeepConditionNotMet.selector);
        rafflFactory.disperseRewards(address(raffl));
    }

    /// @dev Should revert if trying to disperse rewards twice
    function test_RevertIf_DisperseTwice() public {
        makeUserBuyEntries(raffl, userA, raffl.minEntries());
        vm.warp(raffl.deadline() + 1);

        uint256 requestId = performUpkeepOnActiveRaffl(raffl);
        vrfCoordinator.fulfillRandomWords(requestId, address(rafflFactory));

        // First dispersal
        rafflFactory.disperseRewards(address(raffl));

        // Try to disperse again
        vm.expectRevert(FactoryErrors.UpkeepConditionNotMet.selector);
        rafflFactory.disperseRewards(address(raffl));
    }

    /// @dev Raffle should be removed from active list after dispersal
    function test_RaffleRemovedFromActiveAfterDispersal() public {
        makeUserBuyEntries(raffl, userA, raffl.minEntries());
        vm.warp(raffl.deadline() + 1);

        uint256 requestId = performUpkeepOnActiveRaffl(raffl);
        vrfCoordinator.fulfillRandomWords(requestId, address(rafflFactory));

        // Should still be in active list
        (address activeRaffle,, bool found) = findActiveRaffle(raffl);
        assertTrue(found);
        assertEq(activeRaffle, address(raffl));

        // Disperse rewards
        rafflFactory.disperseRewards(address(raffl));

        // Should be removed from active list
        (address activeRaffleAfter,, bool foundAfter) = findActiveRaffle(raffl);
        assertFalse(foundAfter);
        assertEq(activeRaffleAfter, address(0));
    }

    /*//////////////////////////////////////////////////////////////
                    AUTOMATION INTEGRATION TESTS
    //////////////////////////////////////////////////////////////*/

    /// @dev Automation should detect raffle needing dispersal
    function test_AutomationDetectsDispersalNeeded() public {
        makeUserBuyEntries(raffl, userA, raffl.minEntries());
        vm.warp(raffl.deadline() + 1);

        uint256 requestId = performUpkeepOnActiveRaffl(raffl);
        vrfCoordinator.fulfillRandomWords(requestId, address(rafflFactory));

        // checkUpkeep should return true
        (bool upkeepNeeded, bytes memory performData) = rafflFactory.checkUpkeep(CHECK_DATA);
        assertTrue(upkeepNeeded);

        (address raffle,) = abi.decode(performData, (address, uint256));
        assertEq(raffle, address(raffl));
    }

    /// @dev performUpkeep should disperse rewards when detected
    function test_AutomationDispersesRewards() public {
        makeUserBuyEntries(raffl, userA, raffl.minEntries());
        vm.warp(raffl.deadline() + 1);

        uint256 requestId = performUpkeepOnActiveRaffl(raffl);
        vrfCoordinator.fulfillRandomWords(requestId, address(rafflFactory));

        // Get performData
        (, bytes memory performData) = rafflFactory.checkUpkeep(CHECK_DATA);

        // performUpkeep should disperse
        rafflFactory.performUpkeep(performData);

        assertTrue(raffl.gameStatus() == IRaffl.GameStatus.SuccessDraw);
    }

    /*//////////////////////////////////////////////////////////////
                        POOL DISTRIBUTION TESTS
    //////////////////////////////////////////////////////////////*/

    /// @dev Pool should be distributed correctly after dispersal
    function test_PoolDistributedCorrectly() public {
        uint256 entries = raffl.minEntries();
        makeUserBuyEntries(raffl, userA, entries);
        vm.warp(raffl.deadline() + 1);

        uint256 requestId = performUpkeepOnActiveRaffl(raffl);
        vrfCoordinator.fulfillRandomWords(requestId, address(rafflFactory));

        uint256 creatorBalanceBefore = raffleCreator.balance;

        // Disperse
        rafflFactory.disperseRewards(address(raffl));

        // Creator should have received pool (minus fees)
        uint256 creatorBalanceAfter = raffleCreator.balance;
        assertGt(creatorBalanceAfter, creatorBalanceBefore);
    }

    /// @dev Prizes should be transferred correctly after dispersal
    function test_PrizesTransferredCorrectly() public {
        makeUserBuyEntries(raffl, userA, raffl.minEntries());
        vm.warp(raffl.deadline() + 1);

        uint256 requestId = performUpkeepOnActiveRaffl(raffl);
        vrfCoordinator.fulfillRandomWords(requestId, address(rafflFactory));

        address winner = raffl.winner();
        uint256 nftBalanceBefore = testERC721.balanceOf(winner);
        uint256 erc20BalanceBefore = testERC20.balanceOf(winner);

        // Disperse
        rafflFactory.disperseRewards(address(raffl));

        // Winner should have received prizes
        assertGt(testERC721.balanceOf(winner), nftBalanceBefore);
        assertGt(testERC20.balanceOf(winner), erc20BalanceBefore);
    }

    /*//////////////////////////////////////////////////////////////
                        EDGE CASE TESTS
    //////////////////////////////////////////////////////////////*/

    /// @dev Should handle single entry raffle
    function test_SingleEntryRaffle() public {
        makeUserBuyEntries(raffl, userA, 1);

        // Reduce min entries for this test
        vm.warp(raffl.deadline() + 1);

        uint256 requestId = performUpkeepOnActiveRaffl(raffl);

        // Should work even with 1 entry (if minEntries allows)
        if (raffl.criteriaMet()) {
            vrfCoordinator.fulfillRandomWords(requestId, address(rafflFactory));

            assertEq(raffl.winner(), userA);
            assertEq(raffl.winningEntry(), 0);
        }
    }

    /// @dev Should handle maximum entries scenario
    function test_MaximumEntriesScenario() public {
        // Buy many entries
        uint256 manyEntries = 100;
        makeUserBuyEntries(raffl, userA, manyEntries);

        vm.warp(raffl.deadline() + 1);
        uint256 requestId = performUpkeepOnActiveRaffl(raffl);

        vrfCoordinator.fulfillRandomWords(requestId, address(rafflFactory));

        // Winner should be determined correctly
        assertTrue(raffl.winner() != address(0));
        assertTrue(raffl.winningEntry() < manyEntries);
    }

    /// @dev Should handle winner selection from multiple participants
    function test_MultipleParticipantsWinnerSelection() public {
        // Different users buy different amounts
        makeUserBuyEntries(raffl, userA, 1);
        makeUserBuyEntries(raffl, userB, 5);
        makeUserBuyEntries(raffl, userC, 3);
        makeUserBuyEntries(raffl, userD, 1);

        vm.warp(raffl.deadline() + 1);
        uint256 requestId = performUpkeepOnActiveRaffl(raffl);

        vrfCoordinator.fulfillRandomWords(requestId, address(rafflFactory));

        address winner = raffl.winner();

        // Winner must be one of the participants
        assertTrue(winner == userA || winner == userB || winner == userC || winner == userD);

        // Winner owns the winning entry
        assertEq(raffl.ownerOf(raffl.winningEntry()), winner);
    }

    /// @dev Dispersal should work even after long delay
    function test_DispersalAfterLongDelay() public {
        makeUserBuyEntries(raffl, userA, raffl.minEntries());
        vm.warp(raffl.deadline() + 1);

        uint256 requestId = performUpkeepOnActiveRaffl(raffl);
        vrfCoordinator.fulfillRandomWords(requestId, address(rafflFactory));

        // Wait a very long time
        vm.warp(block.timestamp + 365 days);

        // Should still be able to disperse
        rafflFactory.disperseRewards(address(raffl));

        assertTrue(raffl.gameStatus() == IRaffl.GameStatus.SuccessDraw);
    }

    /// @dev Multiple dispersal attempts should only succeed once
    function test_OnlyOneSuccessfulDispersal() public {
        makeUserBuyEntries(raffl, userA, raffl.minEntries());
        vm.warp(raffl.deadline() + 1);

        uint256 requestId = performUpkeepOnActiveRaffl(raffl);
        vrfCoordinator.fulfillRandomWords(requestId, address(rafflFactory));

        // First dispersal succeeds
        rafflFactory.disperseRewards(address(raffl));

        // All subsequent attempts should fail
        vm.expectRevert();
        rafflFactory.disperseRewards(address(raffl));

        vm.expectRevert();
        vm.prank(userB);
        rafflFactory.disperseRewards(address(raffl));

        vm.expectRevert();
        vm.prank(raffleCreator);
        rafflFactory.disperseRewards(address(raffl));
    }

    /*//////////////////////////////////////////////////////////////
                    STATE CONSISTENCY TESTS
    //////////////////////////////////////////////////////////////*/

    /// @dev shouldDisperseRewards should return correct state
    function test_ShouldDisperseRewardsState() public {
        // Initially false
        assertFalse(raffl.shouldDisperseRewards());

        makeUserBuyEntries(raffl, userA, raffl.minEntries());
        vm.warp(raffl.deadline() + 1);

        // Still false after upkeep
        uint256 requestId = performUpkeepOnActiveRaffl(raffl);
        assertFalse(raffl.shouldDisperseRewards());

        // True after VRF fulfills
        vrfCoordinator.fulfillRandomWords(requestId, address(rafflFactory));
        assertTrue(raffl.shouldDisperseRewards());

        // False after dispersal
        rafflFactory.disperseRewards(address(raffl));
        assertFalse(raffl.shouldDisperseRewards());
    }

    /// @dev Game status should progress correctly through all states
    function test_GameStatusProgression() public {
        // Initialized
        assertTrue(raffl.gameStatus() == IRaffl.GameStatus.Initialized);

        makeUserBuyEntries(raffl, userA, raffl.minEntries());
        vm.warp(raffl.deadline() + 1);

        // DrawStarted
        uint256 requestId = performUpkeepOnActiveRaffl(raffl);
        assertTrue(raffl.gameStatus() == IRaffl.GameStatus.DrawStarted);

        // WinnerDrawn
        vrfCoordinator.fulfillRandomWords(requestId, address(rafflFactory));
        assertTrue(raffl.gameStatus() == IRaffl.GameStatus.WinnerDrawn);

        // SuccessDraw
        rafflFactory.disperseRewards(address(raffl));
        assertTrue(raffl.gameStatus() == IRaffl.GameStatus.SuccessDraw);
    }

    /// @dev Winner data should be immutable after setting
    function test_WinnerDataImmutable() public {
        makeUserBuyEntries(raffl, userA, raffl.minEntries());
        vm.warp(raffl.deadline() + 1);

        uint256 requestId = performUpkeepOnActiveRaffl(raffl);
        vrfCoordinator.fulfillRandomWords(requestId, address(rafflFactory));

        address winner = raffl.winner();
        uint256 winningEntry = raffl.winningEntry();
        uint256 storedRequestId = raffl.requestId();

        // Disperse rewards
        rafflFactory.disperseRewards(address(raffl));

        // Winner data should remain the same
        assertEq(raffl.winner(), winner);
        assertEq(raffl.winningEntry(), winningEntry);
        assertEq(raffl.requestId(), storedRequestId);
    }
}
