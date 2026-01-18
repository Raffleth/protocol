// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.33;

import { Raffl } from "../../src/Raffl.sol";
import { RafflFactory } from "../../src/RafflFactory.sol";
import { IRaffl } from "../../src/interfaces/IRaffl.sol";
import { Errors } from "../../src/libraries/RafflFactoryErrors.sol";

import { Common } from "../utils/Common.sol";

contract RafflVRFEdgeCasesTest is Common {
    Raffl raffl;
    Raffl raffl2;
    Raffl raffl3;

    function setUp() public virtual {
        fundAndSetPrizes(raffleCreator);
    }

    /*//////////////////////////////////////////////////////////////
                        RANDOM NUMBER EDGE CASES
    //////////////////////////////////////////////////////////////*/

    /// @dev Should handle VRF returning 0 as random number
    function test_VRFReturnsZero() public {
        raffl = createNewRaffle(raffleCreator);

        makeUserBuyEntries(raffl, userA, 5);
        makeUserBuyEntries(raffl, userB, 5);

        vm.warp(raffl.deadline());
        uint256 requestId = performUpkeepOnActiveRaffl(raffl);

        // Manually fulfill with 0
        uint256[] memory randomWords = new uint256[](1);
        randomWords[0] = 0;

        vm.prank(address(vrfCoordinator));
        vrfCoordinator.fulfillRandomWordsWithOverride(requestId, address(rafflFactory), randomWords);

        // Winner should be entry 0 (0 % 10 = 0)
        assertEq(raffl.winningEntry(), 0);
        assertEq(raffl.winner(), userA); // userA owns entries 0-4
    }

    /// @dev Should handle VRF returning max uint256
    function test_VRFReturnsMaxUint256() public {
        raffl = createNewRaffle(raffleCreator);

        makeUserBuyEntries(raffl, userA, 5);
        makeUserBuyEntries(raffl, userB, 5);

        vm.warp(raffl.deadline());
        uint256 requestId = performUpkeepOnActiveRaffl(raffl);

        // Manually fulfill with max uint256
        uint256[] memory randomWords = new uint256[](1);
        randomWords[0] = type(uint256).max;

        vm.prank(address(vrfCoordinator));
        vrfCoordinator.fulfillRandomWordsWithOverride(requestId, address(rafflFactory), randomWords);

        // Winner should be (type(uint256).max % 10)
        uint256 expectedWinningEntry = type(uint256).max % 10;
        assertEq(raffl.winningEntry(), expectedWinningEntry);
    }

    /// @dev Should handle VRF returning exact multiple of totalEntries
    function test_VRFReturnsExactMultiple() public {
        raffl = createNewRaffle(raffleCreator);

        makeUserBuyEntries(raffl, userA, 5);
        makeUserBuyEntries(raffl, userB, 5);
        // Total entries = 10

        vm.warp(raffl.deadline());
        uint256 requestId = performUpkeepOnActiveRaffl(raffl);

        // Manually fulfill with exact multiple of total entries
        uint256[] memory randomWords = new uint256[](1);
        randomWords[0] = 100; // 100 % 10 = 0

        vm.prank(address(vrfCoordinator));
        vrfCoordinator.fulfillRandomWordsWithOverride(requestId, address(rafflFactory), randomWords);

        assertEq(raffl.winningEntry(), 0);
        assertEq(raffl.winner(), userA);
    }

    /// @dev Should handle VRF with single entry raffle
    function test_VRFSingleEntryRaffle() public {
        vm.prank(raffleCreator);
        raffl = Raffl(
            rafflFactory.createRaffle(
                address(0),
                ENTRY_PRICE,
                1, // minEntries = 1
                block.timestamp + DEADLINE_FROM_NOW,
                prizes,
                tokenGates,
                extraRecipient
            )
        );

        makeUserBuyEntries(raffl, userA, 1);

        vm.warp(raffl.deadline());
        uint256 requestId = performUpkeepOnActiveRaffl(raffl);

        // Any random number should result in winner being userA (x % 1 = 0)
        uint256[] memory randomWords = new uint256[](1);
        randomWords[0] = 12345678;

        vm.prank(address(vrfCoordinator));
        vrfCoordinator.fulfillRandomWordsWithOverride(requestId, address(rafflFactory), randomWords);

        assertEq(raffl.winningEntry(), 0);
        assertEq(raffl.winner(), userA);
    }

    /*//////////////////////////////////////////////////////////////
                    CONCURRENT VRF REQUESTS
    //////////////////////////////////////////////////////////////*/

    /// @dev Should handle multiple raffles with concurrent VRF requests
    function test_ConcurrentVRFRequests() public {
        // Create first raffle with initial prizes
        raffl = createNewRaffle(raffleCreator);
        
        // Clear prizes array and create fresh prizes for second raffle
        delete prizes;
        deployErc20AndFund(raffleCreator);
        deployErc721AndFund(raffleCreator);
        
        vm.startPrank(raffleCreator);
        testERC20.approve(address(rafflFactory), ERC20_AMOUNT);
        testERC721.approve(address(rafflFactory), ERC721_TOKEN_ID);
        vm.stopPrank();
        
        prizes.push(IRaffl.Prize(address(testERC20), IRaffl.AssetType.ERC20, ERC20_AMOUNT));
        prizes.push(IRaffl.Prize(address(testERC721), IRaffl.AssetType.ERC721, ERC721_TOKEN_ID));
        
        raffl2 = createNewRaffle(raffleCreator);

        // Buy entries for both
        makeUserBuyEntries(raffl, userA, MIN_ENTRIES);
        makeUserBuyEntries(raffl2, userB, MIN_ENTRIES);

        // Process both to DrawStarted
        vm.warp(raffl.deadline());
        uint256 requestId1 = performUpkeepOnActiveRaffl(raffl);
        uint256 requestId2 = performUpkeepOnActiveRaffl(raffl2);

        // Both should be in DrawStarted state
        assertEq(uint8(raffl.gameStatus()), uint8(IRaffl.GameStatus.DrawStarted));
        assertEq(uint8(raffl2.gameStatus()), uint8(IRaffl.GameStatus.DrawStarted));

        // Fulfill VRF for both (in reverse order)
        vrfCoordinator.fulfillRandomWords(requestId2, address(rafflFactory));
        vrfCoordinator.fulfillRandomWords(requestId1, address(rafflFactory));

        // Both should have winners
        assertEq(uint8(raffl.gameStatus()), uint8(IRaffl.GameStatus.WinnerDrawn));
        assertEq(uint8(raffl2.gameStatus()), uint8(IRaffl.GameStatus.WinnerDrawn));

        // Disperse rewards for both
        raffl.disperseRewards();
        raffl2.disperseRewards();

        assertEq(uint8(raffl.gameStatus()), uint8(IRaffl.GameStatus.SuccessDraw));
        assertEq(uint8(raffl2.gameStatus()), uint8(IRaffl.GameStatus.SuccessDraw));
    }

    /// @dev Should correctly track separate VRF requests for each raffle
    function test_SeparateVRFRequestTracking() public {
        raffl = createNewRaffle(raffleCreator);

        makeUserBuyEntries(raffl, userA, MIN_ENTRIES);
        vm.warp(raffl.deadline());
        uint256 requestId = performUpkeepOnActiveRaffl(raffl);

        // Check VRF request info
        (uint256 storedRequestId, uint256 requestTime, RafflFactory.VRFStatus status) =
            rafflFactory.getVRFRequestInfo(address(raffl));

        assertEq(storedRequestId, requestId);
        assertTrue(requestTime > 0);
        assertEq(uint8(status), uint8(RafflFactory.VRFStatus.Pending));

        // Fulfill VRF
        vrfCoordinator.fulfillRandomWords(requestId, address(rafflFactory));

        // Check status updated
        (, , RafflFactory.VRFStatus newStatus) = rafflFactory.getVRFRequestInfo(address(raffl));
        assertEq(uint8(newStatus), uint8(RafflFactory.VRFStatus.Fulfilled));
    }

    /*//////////////////////////////////////////////////////////////
                    VRF TIMEOUT AND RETRY
    //////////////////////////////////////////////////////////////*/

    /// @dev Should correctly identify timed out VRF request
    function test_VRFTimeoutDetection() public {
        raffl = createNewRaffle(raffleCreator);

        makeUserBuyEntries(raffl, userA, MIN_ENTRIES);
        vm.warp(raffl.deadline());
        performUpkeepOnActiveRaffl(raffl);

        // Not timed out yet
        assertFalse(rafflFactory.hasVRFRequestTimedOut(address(raffl)));

        // Warp to just before timeout
        vm.warp(block.timestamp + rafflFactory.VRF_REQUEST_TIMEOUT() - 1);
        assertFalse(rafflFactory.hasVRFRequestTimedOut(address(raffl)));

        // Warp to exactly timeout
        vm.warp(block.timestamp + 1);
        assertTrue(rafflFactory.hasVRFRequestTimedOut(address(raffl)));
    }

    /// @dev Should allow VRF retry and update request info
    function test_VRFRetryUpdatesRequestInfo() public {
        raffl = createNewRaffle(raffleCreator);

        makeUserBuyEntries(raffl, userA, MIN_ENTRIES);
        vm.warp(raffl.deadline());
        uint256 originalRequestId = performUpkeepOnActiveRaffl(raffl);

        (uint256 firstRequestId, uint256 firstRequestTime, ) = rafflFactory.getVRFRequestInfo(address(raffl));

        // Warp forward (but not to timeout)
        vm.warp(block.timestamp + 1 hours);

        // Retry VRF
        rafflFactory.retryVRFRequest(address(raffl));

        (uint256 newRequestId, uint256 newRequestTime, RafflFactory.VRFStatus newStatus) =
            rafflFactory.getVRFRequestInfo(address(raffl));

        // New request should have different ID and later time
        assertTrue(newRequestId != originalRequestId);
        assertTrue(newRequestTime > firstRequestTime);
        assertEq(uint8(newStatus), uint8(RafflFactory.VRFStatus.Pending));
    }

    /// @dev Should allow VRF fulfillment after retry
    function test_VRFFulfillmentAfterRetry() public {
        raffl = createNewRaffle(raffleCreator);

        makeUserBuyEntries(raffl, userA, MIN_ENTRIES);
        vm.warp(raffl.deadline());
        performUpkeepOnActiveRaffl(raffl);

        // Retry VRF
        vm.recordLogs();
        rafflFactory.retryVRFRequest(address(raffl));

        // Get new request ID from logs
        (uint256 newRequestId, , ) = rafflFactory.getVRFRequestInfo(address(raffl));

        // Fulfill with new request ID
        vrfCoordinator.fulfillRandomWords(newRequestId, address(rafflFactory));

        assertEq(uint8(raffl.gameStatus()), uint8(IRaffl.GameStatus.WinnerDrawn));
        assertTrue(raffl.winner() != address(0));
    }

    /// @dev Should handle emergency fail after VRF timeout
    function test_EmergencyFailAfterVRFTimeout() public {
        raffl = createNewRaffle(raffleCreator);

        makeUserBuyEntries(raffl, userA, MIN_ENTRIES);
        vm.warp(raffl.deadline());
        performUpkeepOnActiveRaffl(raffl);

        // Warp past timeout
        vm.warp(block.timestamp + rafflFactory.VRF_REQUEST_TIMEOUT() + 1);

        // Emergency fail
        rafflFactory.emergencyFailRaffle(address(raffl));

        // Should be in FailedDraw state
        assertEq(uint8(raffl.gameStatus()), uint8(IRaffl.GameStatus.FailedDraw));

        // VRF status should be Failed
        (, , RafflFactory.VRFStatus status) = rafflFactory.getVRFRequestInfo(address(raffl));
        assertEq(uint8(status), uint8(RafflFactory.VRFStatus.Failed));
    }

    /// @dev Should prevent emergency fail before timeout
    function test_RevertIf_EmergencyFailBeforeTimeout() public {
        raffl = createNewRaffle(raffleCreator);

        makeUserBuyEntries(raffl, userA, MIN_ENTRIES);
        vm.warp(raffl.deadline());
        performUpkeepOnActiveRaffl(raffl);

        // Try to emergency fail before timeout
        vm.expectRevert(Errors.VRFRequestNotTimedOut.selector);
        rafflFactory.emergencyFailRaffle(address(raffl));
    }

    /// @dev Should prevent retry after VRF fulfilled
    function test_RevertIf_RetryAfterFulfillment() public {
        raffl = createNewRaffle(raffleCreator);

        makeUserBuyEntries(raffl, userA, MIN_ENTRIES);
        vm.warp(raffl.deadline());
        uint256 requestId = performUpkeepOnActiveRaffl(raffl);

        // Fulfill VRF
        vrfCoordinator.fulfillRandomWords(requestId, address(rafflFactory));

        // Try to retry after fulfillment
        vm.expectRevert(Errors.VRFRequestNotPending.selector);
        rafflFactory.retryVRFRequest(address(raffl));
    }

    /// @dev Should prevent retry on non-existent raffle
    function test_RevertIf_RetryOnInvalidRaffle() public {
        vm.expectRevert(Errors.InvalidVRFRequest.selector);
        rafflFactory.retryVRFRequest(address(0x1234));
    }

    /*//////////////////////////////////////////////////////////////
                    VRF REQUEST ID MAPPING
    //////////////////////////////////////////////////////////////*/

    /// @dev Should correctly map multiple request IDs from retries
    function test_MultipleRetryRequestIDMapping() public {
        raffl = createNewRaffle(raffleCreator);

        makeUserBuyEntries(raffl, userA, MIN_ENTRIES);
        vm.warp(raffl.deadline());
        performUpkeepOnActiveRaffl(raffl);

        // Multiple retries
        rafflFactory.retryVRFRequest(address(raffl));
        (uint256 secondRequestId, , ) = rafflFactory.getVRFRequestInfo(address(raffl));

        rafflFactory.retryVRFRequest(address(raffl));
        (uint256 thirdRequestId, , ) = rafflFactory.getVRFRequestInfo(address(raffl));

        // Fulfill the latest request
        vrfCoordinator.fulfillRandomWords(thirdRequestId, address(rafflFactory));

        assertEq(uint8(raffl.gameStatus()), uint8(IRaffl.GameStatus.WinnerDrawn));
    }

    /*//////////////////////////////////////////////////////////////
                    WINNER SELECTION DETERMINISM
    //////////////////////////////////////////////////////////////*/

    /// @dev Should select winner deterministically based on random number
    function test_WinnerSelectionDeterminism() public {
        raffl = createNewRaffle(raffleCreator);

        makeUserBuyEntries(raffl, userA, 3); // entries 0, 1, 2
        makeUserBuyEntries(raffl, userB, 2); // entries 3, 4
        makeUserBuyEntries(raffl, userC, 5); // entries 5, 6, 7, 8, 9
        // Total: 10 entries

        vm.warp(raffl.deadline());
        uint256 requestId = performUpkeepOnActiveRaffl(raffl);

        // Test different random numbers
        uint256[] memory randomWords = new uint256[](1);

        // Random that selects entry 0 (userA)
        randomWords[0] = 10; // 10 % 10 = 0
        vm.prank(address(vrfCoordinator));
        vrfCoordinator.fulfillRandomWordsWithOverride(requestId, address(rafflFactory), randomWords);
        assertEq(raffl.winner(), userA);
        assertEq(raffl.winningEntry(), 0);
    }

    /// @dev Should select correct winner for each entry owner
    function test_WinnerSelectionForEachOwner() public {
        // Test random numbers that would select each user
        uint256[3] memory testCases = [
            uint256(2),  // Entry 2 -> userA
            uint256(4),  // Entry 4 -> userB
            uint256(7)   // Entry 7 -> userC
        ];
        address[3] memory expectedWinners = [userA, userB, userC];

        for (uint256 i = 0; i < testCases.length; i++) {
            // Reset prizes array and deploy fresh prizes for each iteration
            delete prizes;
            delete tokenGates;
            
            // Mint fresh ERC721 for each raffle (unique token ID per iteration)
            uint256 freshTokenId = 1000 + i;
            testERC721.mint(raffleCreator, freshTokenId);
            testERC20.mint(raffleCreator, ERC20_AMOUNT);
            
            vm.startPrank(raffleCreator);
            testERC20.approve(address(rafflFactory), ERC20_AMOUNT);
            testERC721.approve(address(rafflFactory), freshTokenId);
            vm.stopPrank();
            
            prizes.push(IRaffl.Prize(address(testERC20), IRaffl.AssetType.ERC20, ERC20_AMOUNT));
            prizes.push(IRaffl.Prize(address(testERC721), IRaffl.AssetType.ERC721, freshTokenId));
            
            raffl = createNewRaffle(raffleCreator);

            makeUserBuyEntries(raffl, userA, 3);
            makeUserBuyEntries(raffl, userB, 2);
            makeUserBuyEntries(raffl, userC, 5);

            vm.warp(raffl.deadline());
            uint256 requestId = performUpkeepOnActiveRaffl(raffl);

            uint256[] memory randomWords = new uint256[](1);
            randomWords[0] = testCases[i];

            vm.prank(address(vrfCoordinator));
            vrfCoordinator.fulfillRandomWordsWithOverride(requestId, address(rafflFactory), randomWords);

            assertEq(raffl.winner(), expectedWinners[i]);
        }
    }

    /*//////////////////////////////////////////////////////////////
                    VRF WITH DIFFERENT RAFFLE STATES
    //////////////////////////////////////////////////////////////*/

    /// @dev Should not have VRF request for failed criteria raffle
    function test_NoVRFRequestForFailedCriteria() public {
        raffl = createNewRaffle(raffleCreator);

        // Only 1 entry, need MIN_ENTRIES
        makeUserBuyEntries(raffl, userA, 1);

        vm.warp(raffl.deadline());
        performUpkeepOnActiveRaffl(raffl);

        // Should be in FailedDraw state
        assertEq(uint8(raffl.gameStatus()), uint8(IRaffl.GameStatus.FailedDraw));

        // No VRF request should exist
        (uint256 requestId, , RafflFactory.VRFStatus status) = rafflFactory.getVRFRequestInfo(address(raffl));
        assertEq(requestId, 0);
        assertEq(uint8(status), uint8(RafflFactory.VRFStatus.None));
    }
}
