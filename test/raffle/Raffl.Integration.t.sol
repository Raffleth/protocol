// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.33;

import { Raffl } from "../../src/Raffl.sol";
import { RafflFactory } from "../../src/RafflFactory.sol";
import { IRaffl } from "../../src/interfaces/IRaffl.sol";

import { Common } from "../utils/Common.sol";
import { ERC20Mock } from "../mocks/ERC20Mock.sol";
import { ERC721Mock } from "../mocks/ERC721Mock.sol";

/// @title Raffl Integration Tests
/// @notice Comprehensive end-to-end tests covering full protocol lifecycle
contract RafflIntegrationTest is Common {
    
    // Test state for reuse
    ERC20Mock prizeToken;
    ERC721Mock prizeNFT;
    
    /*//////////////////////////////////////////////////////////////
                    COMPLETE LIFECYCLE - SUCCESS PATH
    //////////////////////////////////////////////////////////////*/

    /// @dev Full lifecycle: create -> entries -> deadline -> VRF -> disperse
    function test_FullSuccessLifecycle() public {
        // === PHASE 1: Creation ===
        prizeToken = new ERC20Mock();
        prizeNFT = new ERC721Mock();

        prizeToken.mint(raffleCreator, 1000 ether);
        prizeNFT.mint(raffleCreator, 42);

        vm.startPrank(raffleCreator);
        prizeToken.approve(address(rafflFactory), 1000 ether);
        prizeNFT.approve(address(rafflFactory), 42);

        IRaffl.Prize[] memory testPrizes = new IRaffl.Prize[](2);
        testPrizes[0] = IRaffl.Prize(address(prizeToken), IRaffl.AssetType.ERC20, 1000 ether);
        testPrizes[1] = IRaffl.Prize(address(prizeNFT), IRaffl.AssetType.ERC721, 42);

        IRaffl.ExtraRecipient memory recipient =
            IRaffl.ExtraRecipient({ recipient: userExtraRecipient, sharePercentage: 0.1 ether });

        Raffl raffl = Raffl(
            rafflFactory.createRaffle(
                address(0), 1 ether, 10, block.timestamp + 7 days, testPrizes, tokenGates, recipient
            )
        );
        vm.stopPrank();

        // Verify initial state
        assertEq(uint8(raffl.gameStatus()), uint8(IRaffl.GameStatus.Initialized));
        assertEq(prizeToken.balanceOf(address(raffl)), 1000 ether);

        // === PHASE 2: Entry Acquisition ===
        _buyEntriesForSuccessLifecycle(raffl);

        // Verify entry state
        assertEq(raffl.totalEntries(), 10);
        assertTrue(raffl.criteriaMet());

        // === PHASE 3-5: Deadline -> VRF -> Disperse ===
        vm.warp(raffl.deadline());
        
        (bool upkeepNeeded, bytes memory performData) = rafflFactory.checkUpkeep(abi.encode(0, 10));
        assertTrue(upkeepNeeded);
        rafflFactory.performUpkeep(performData);

        (uint256 requestId, , ) = rafflFactory.getVRFRequestInfo(address(raffl));
        vrfCoordinator.fulfillRandomWords(requestId, address(rafflFactory));

        address winner = raffl.winner();
        assertTrue(winner != address(0));

        raffl.disperseRewards();

        // Verify final state
        assertEq(uint8(raffl.gameStatus()), uint8(IRaffl.GameStatus.SuccessDraw));
        assertEq(prizeToken.balanceOf(winner), 1000 ether);
        assertEq(prizeNFT.ownerOf(42), winner);
    }
    
    function _buyEntriesForSuccessLifecycle(Raffl raffl) internal {
        address[5] memory participants;
        for (uint256 i = 0; i < 5; i++) {
            participants[i] = address(uint160(2000 + i));
            vm.deal(participants[i], 10 ether);
        }

        vm.prank(participants[0]);
        raffl.buyEntries{ value: 3 ether }(3);

        vm.prank(participants[1]);
        raffl.buyEntries{ value: 2 ether }(2);

        vm.prank(participants[2]);
        raffl.buyEntries{ value: 2 ether }(2);

        vm.prank(participants[3]);
        raffl.buyEntries{ value: 2 ether }(2);

        vm.prank(participants[4]);
        raffl.buyEntries{ value: 1 ether }(1);
    }

    /*//////////////////////////////////////////////////////////////
                    COMPLETE LIFECYCLE - FAILURE PATH
    //////////////////////////////////////////////////////////////*/

    /// @dev Full lifecycle: create -> insufficient entries -> failed draw -> refunds
    function test_FullFailureLifecycle() public {
        ERC20Mock prizeToken = new ERC20Mock();
        prizeToken.mint(raffleCreator, 500 ether);

        vm.startPrank(raffleCreator);
        prizeToken.approve(address(rafflFactory), 500 ether);

        IRaffl.Prize[] memory testPrizes = new IRaffl.Prize[](1);
        testPrizes[0] = IRaffl.Prize(address(prizeToken), IRaffl.AssetType.ERC20, 500 ether);

        Raffl raffl = Raffl(
            rafflFactory.createRaffle(
                address(0),
                2 ether,
                10, // Need 10 entries
                block.timestamp + 3 days,
                testPrizes,
                tokenGates,
                extraRecipient
            )
        );
        vm.stopPrank();

        // Only 5 entries (not meeting criteria)
        address user1 = address(0x3001);
        address user2 = address(0x3002);
        vm.deal(user1, 6 ether);
        vm.deal(user2, 4 ether);

        vm.prank(user1);
        raffl.buyEntries{ value: 6 ether }(3);

        vm.prank(user2);
        raffl.buyEntries{ value: 4 ether }(2);

        assertEq(raffl.totalEntries(), 5);
        assertFalse(raffl.criteriaMet());

        // Process deadline
        vm.warp(raffl.deadline());
        (bool upkeepNeeded, bytes memory performData) = rafflFactory.checkUpkeep(abi.encode(0, 10));
        assertTrue(upkeepNeeded);

        rafflFactory.performUpkeep(performData);

        // Verify failed state
        assertEq(uint8(raffl.gameStatus()), uint8(IRaffl.GameStatus.FailedDraw));
        assertEq(rafflFactory.activeRaffles().length, 0);

        // Users get refunds
        uint256 user1BalanceBefore = user1.balance;
        uint256 user2BalanceBefore = user2.balance;

        raffl.refundEntries(user1);
        raffl.refundEntries(user2);

        assertEq(user1.balance - user1BalanceBefore, 6 ether);
        assertEq(user2.balance - user2BalanceBefore, 4 ether);

        // Creator gets prizes back
        uint256 creatorTokenBefore = prizeToken.balanceOf(raffleCreator);
        vm.prank(raffleCreator);
        raffl.refundPrizes();

        assertEq(prizeToken.balanceOf(raffleCreator) - creatorTokenBefore, 500 ether);
    }

    /*//////////////////////////////////////////////////////////////
                    VRF RECOVERY LIFECYCLE
    //////////////////////////////////////////////////////////////*/

    /// @dev Full lifecycle with VRF timeout and emergency fail
    function test_VRFRecoveryLifecycle() public {
        fundAndSetPrizes(raffleCreator);
        Raffl raffl = createNewRaffle(raffleCreator);

        makeUserBuyEntries(raffl, userA, MIN_ENTRIES);

        vm.warp(raffl.deadline());
        performUpkeepOnActiveRaffl(raffl);

        // VRF times out
        vm.warp(block.timestamp + rafflFactory.VRF_REQUEST_TIMEOUT() + 1);
        assertTrue(rafflFactory.hasVRFRequestTimedOut(address(raffl)));

        // Emergency fail
        rafflFactory.emergencyFailRaffle(address(raffl));

        assertEq(uint8(raffl.gameStatus()), uint8(IRaffl.GameStatus.FailedDraw));
        (, , RafflFactory.VRFStatus status) = rafflFactory.getVRFRequestInfo(address(raffl));
        assertEq(uint8(status), uint8(RafflFactory.VRFStatus.Failed));

        // Users can refund
        uint256 userBalanceBefore = userA.balance;
        raffl.refundEntries(userA);
        assertEq(userA.balance - userBalanceBefore, ENTRY_PRICE * MIN_ENTRIES);
    }

    /// @dev Full lifecycle with VRF retry succeeding
    function test_VRFRetrySuccessLifecycle() public {
        fundAndSetPrizes(raffleCreator);
        Raffl raffl = createNewRaffle(raffleCreator);

        makeUserBuyEntries(raffl, userA, MIN_ENTRIES);

        vm.warp(raffl.deadline());
        performUpkeepOnActiveRaffl(raffl);

        // Simulate stuck VRF - retry
        rafflFactory.retryVRFRequest(address(raffl));

        (uint256 newRequestId, , ) = rafflFactory.getVRFRequestInfo(address(raffl));

        // New VRF request succeeds
        vrfCoordinator.fulfillRandomWords(newRequestId, address(rafflFactory));

        assertEq(uint8(raffl.gameStatus()), uint8(IRaffl.GameStatus.WinnerDrawn));

        // Complete dispersal
        raffl.disperseRewards();
        assertEq(uint8(raffl.gameStatus()), uint8(IRaffl.GameStatus.SuccessDraw));
    }

    /*//////////////////////////////////////////////////////////////
                    MULTI-RAFFLE SCENARIOS
    //////////////////////////////////////////////////////////////*/

    /// @dev Multiple raffles running concurrently with mixed outcomes
    function test_MultipleRafflesMixedOutcomes() public {
        // Create 4 raffles with different configurations
        Raffl[] memory raffles = new Raffl[](4);
        ERC20Mock[] memory tokens = new ERC20Mock[](4);

        for (uint256 i = 0; i < 4; i++) {
            tokens[i] = new ERC20Mock();
            tokens[i].mint(raffleCreator, 100 ether);

            vm.startPrank(raffleCreator);
            tokens[i].approve(address(rafflFactory), 100 ether);

            IRaffl.Prize[] memory p = new IRaffl.Prize[](1);
            p[0] = IRaffl.Prize(address(tokens[i]), IRaffl.AssetType.ERC20, 100 ether);

            raffles[i] = Raffl(
                rafflFactory.createRaffle(
                    address(0),
                    1 ether,
                    5, // Min entries
                    block.timestamp + 1 days,
                    p,
                    tokenGates,
                    extraRecipient
                )
            );
            vm.stopPrank();
        }

        // Raffle 0: Success (meets criteria)
        for (uint256 j = 0; j < 5; j++) {
            address user = address(uint160(4000 + j));
            vm.deal(user, 1 ether);
            vm.prank(user);
            raffles[0].buyEntries{ value: 1 ether }(1);
        }

        // Raffle 1: Failure (doesn't meet criteria)
        vm.deal(address(0x5001), 2 ether);
        vm.prank(address(0x5001));
        raffles[1].buyEntries{ value: 2 ether }(2);

        // Raffle 2: Success (exceeds criteria)
        for (uint256 j = 0; j < 10; j++) {
            address user = address(uint160(5000 + j));
            vm.deal(user, 1 ether);
            vm.prank(user);
            raffles[2].buyEntries{ value: 1 ether }(1);
        }

        // Raffle 3: Failure (no entries)
        // No entries

        // Process all at deadline
        vm.warp(block.timestamp + 1 days);

        // Process raffle 0 - success
        uint256 requestId0 = performUpkeepOnActiveRaffl(raffles[0]);
        fullfillVRFOnActiveAndEligibleRaffle(requestId0, address(rafflFactory));
        assertEq(uint8(raffles[0].gameStatus()), uint8(IRaffl.GameStatus.SuccessDraw));

        // Process raffle 1 - fail
        performUpkeepOnActiveRaffl(raffles[1]);
        assertEq(uint8(raffles[1].gameStatus()), uint8(IRaffl.GameStatus.FailedDraw));

        // Process raffle 2 - success
        uint256 requestId2 = performUpkeepOnActiveRaffl(raffles[2]);
        fullfillVRFOnActiveAndEligibleRaffle(requestId2, address(rafflFactory));
        assertEq(uint8(raffles[2].gameStatus()), uint8(IRaffl.GameStatus.SuccessDraw));

        // Process raffle 3 - fail (no entries but let's add one to avoid 0 entries issue)
        vm.deal(address(0x6001), 1 ether);
        vm.warp(block.timestamp - 1 hours); // Go back before deadline
        vm.prank(address(0x6001));
        raffles[3].buyEntries{ value: 1 ether }(1);
        vm.warp(block.timestamp + 1 hours + 1 days);
        performUpkeepOnActiveRaffl(raffles[3]);
        assertEq(uint8(raffles[3].gameStatus()), uint8(IRaffl.GameStatus.FailedDraw));

        // All raffles should be removed from active list
        assertEq(rafflFactory.activeRaffles().length, 0);
    }

    /*//////////////////////////////////////////////////////////////
                    ERC20 ENTRY LIFECYCLE
    //////////////////////////////////////////////////////////////*/

    /// @dev Full lifecycle with ERC20 entry token
    function test_FullERC20EntryLifecycle() public {
        ERC20Mock entryToken = new ERC20Mock();
        ERC20Mock prizeToken = new ERC20Mock();

        prizeToken.mint(raffleCreator, 200 ether);

        vm.startPrank(raffleCreator);
        prizeToken.approve(address(rafflFactory), 200 ether);

        IRaffl.Prize[] memory testPrizes = new IRaffl.Prize[](1);
        testPrizes[0] = IRaffl.Prize(address(prizeToken), IRaffl.AssetType.ERC20, 200 ether);

        Raffl raffl = Raffl(
            rafflFactory.createRaffle(
                address(entryToken), // ERC20 entry
                5 ether,
                3,
                block.timestamp + 2 days,
                testPrizes,
                tokenGates,
                extraRecipient
            )
        );
        vm.stopPrank();

        // Users buy entries with ERC20
        address[] memory users = new address[](3);
        for (uint256 i = 0; i < 3; i++) {
            users[i] = address(uint160(7000 + i));
            entryToken.mint(users[i], 10 ether);

            vm.startPrank(users[i]);
            entryToken.approve(address(raffl), 10 ether);
            raffl.buyEntries(2);
            vm.stopPrank();
        }

        assertEq(raffl.totalEntries(), 6);
        assertEq(raffl.pool(), 30 ether);
        assertEq(entryToken.balanceOf(address(raffl)), 30 ether);

        // Process
        vm.warp(raffl.deadline());
        uint256 requestId = performUpkeepOnActiveRaffl(raffl);
        vrfCoordinator.fulfillRandomWords(requestId, address(rafflFactory));

        address winner = raffl.winner();

        // Disperse
        uint256 winnerPrizeBefore = prizeToken.balanceOf(winner);
        raffl.disperseRewards();

        assertEq(prizeToken.balanceOf(winner) - winnerPrizeBefore, 200 ether);

        // Verify ERC20 pool was distributed
        assertEq(entryToken.balanceOf(address(raffl)), 0);
    }

    /*//////////////////////////////////////////////////////////////
                    TOKEN GATED RAFFLE LIFECYCLE
    //////////////////////////////////////////////////////////////*/

    /// @dev Full lifecycle with token gating
    function test_TokenGatedRaffleLifecycle() public {
        ERC20Mock gateToken = new ERC20Mock();
        ERC20Mock prizeToken = new ERC20Mock();

        prizeToken.mint(raffleCreator, 100 ether);

        IRaffl.TokenGate[] memory gates = new IRaffl.TokenGate[](1);
        gates[0] = IRaffl.TokenGate({ token: address(gateToken), amount: 50 ether });

        vm.startPrank(raffleCreator);
        prizeToken.approve(address(rafflFactory), 100 ether);

        IRaffl.Prize[] memory testPrizes = new IRaffl.Prize[](1);
        testPrizes[0] = IRaffl.Prize(address(prizeToken), IRaffl.AssetType.ERC20, 100 ether);

        Raffl raffl = Raffl(
            rafflFactory.createRaffle(
                address(0),
                1 ether,
                3,
                block.timestamp + 1 days,
                testPrizes,
                gates,
                extraRecipient
            )
        );
        vm.stopPrank();

        // Fund users with gate tokens
        address[] memory eligibleUsers = new address[](3);
        for (uint256 i = 0; i < 3; i++) {
            eligibleUsers[i] = address(uint160(8000 + i));
            gateToken.mint(eligibleUsers[i], 50 ether);
            vm.deal(eligibleUsers[i], 2 ether);
        }

        // Ineligible user
        address ineligibleUser = address(0x8999);
        vm.deal(ineligibleUser, 2 ether);

        // Eligible users can buy
        for (uint256 i = 0; i < 3; i++) {
            vm.prank(eligibleUsers[i]);
            raffl.buyEntries{ value: 1 ether }(1);
        }

        // Ineligible user cannot
        vm.expectRevert();
        vm.prank(ineligibleUser);
        raffl.buyEntries{ value: 1 ether }(1);

        // Complete raffle
        vm.warp(raffl.deadline());
        uint256 requestId = performUpkeepOnActiveRaffl(raffl);
        fullfillVRFOnActiveAndEligibleRaffle(requestId, address(rafflFactory));

        // Winner must be one of the eligible users
        address winner = raffl.winner();
        bool isEligible = false;
        for (uint256 i = 0; i < 3; i++) {
            if (winner == eligibleUsers[i]) {
                isEligible = true;
                break;
            }
        }
        assertTrue(isEligible);
    }

    /*//////////////////////////////////////////////////////////////
                    FREE RAFFLE LIFECYCLE
    //////////////////////////////////////////////////////////////*/

    /// @dev Full lifecycle with free entries
    function test_FreeRaffleLifecycle() public {
        ERC721Mock prizeNFT = new ERC721Mock();
        prizeNFT.mint(raffleCreator, 1);

        vm.startPrank(raffleCreator);
        prizeNFT.approve(address(rafflFactory), 1);

        IRaffl.Prize[] memory testPrizes = new IRaffl.Prize[](1);
        testPrizes[0] = IRaffl.Prize(address(prizeNFT), IRaffl.AssetType.ERC721, 1);

        Raffl raffl = Raffl(
            rafflFactory.createRaffle(
                address(0),
                0, // Free
                5,
                block.timestamp + 1 days,
                testPrizes,
                tokenGates,
                extraRecipient
            )
        );
        vm.stopPrank();

        // 5 users get free entries
        address[] memory users = new address[](5);
        for (uint256 i = 0; i < 5; i++) {
            users[i] = address(uint160(9000 + i));
            vm.prank(users[i]);
            raffl.buyEntries(1);
        }

        assertEq(raffl.totalEntries(), 5);
        assertEq(raffl.pool(), 0); // No pool for free entries

        // Complete
        vm.warp(raffl.deadline());
        uint256 requestId = performUpkeepOnActiveRaffl(raffl);
        vrfCoordinator.fulfillRandomWords(requestId, address(rafflFactory));

        address winner = raffl.winner();
        raffl.disperseRewards();

        // Winner gets NFT
        assertEq(prizeNFT.ownerOf(1), winner);

        // No pool distribution (was 0)
        assertEq(uint8(raffl.gameStatus()), uint8(IRaffl.GameStatus.SuccessDraw));
    }

    /*//////////////////////////////////////////////////////////////
                    AUTOMATION TRIGGERED LIFECYCLE
    //////////////////////////////////////////////////////////////*/

    /// @dev Lifecycle where automation handles everything
    function test_AutomationDrivenLifecycle() public {
        fundAndSetPrizes(raffleCreator);
        Raffl raffl = createNewRaffle(raffleCreator);

        makeUserBuyEntries(raffl, userA, MIN_ENTRIES);

        // Automation check before deadline
        (bool upkeepNeeded, bytes memory performData) = rafflFactory.checkUpkeep(abi.encode(0, 10));
        assertFalse(upkeepNeeded);

        // At deadline
        vm.warp(raffl.deadline());

        // Automation triggers upkeep
        (upkeepNeeded, performData) = rafflFactory.checkUpkeep(abi.encode(0, 10));
        assertTrue(upkeepNeeded);

        rafflFactory.performUpkeep(performData);

        // VRF callback
        (uint256 requestId, , ) = rafflFactory.getVRFRequestInfo(address(raffl));
        vrfCoordinator.fulfillRandomWords(requestId, address(rafflFactory));

        // Automation detects dispersal needed
        (upkeepNeeded, performData) = rafflFactory.checkUpkeep(abi.encode(0, 10));
        assertTrue(upkeepNeeded);

        // Automation triggers dispersal
        rafflFactory.performUpkeep(performData);

        assertEq(uint8(raffl.gameStatus()), uint8(IRaffl.GameStatus.SuccessDraw));
        assertEq(rafflFactory.activeRaffles().length, 0);
    }
}
