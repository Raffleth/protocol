// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.33;

import { Raffl } from "../../src/Raffl.sol";
import { RafflFactory } from "../../src/RafflFactory.sol";
import { IRaffl } from "../../src/interfaces/IRaffl.sol";
import { Errors } from "../../src/libraries/RafflFactoryErrors.sol";
import { Errors as RafflErrors } from "../../src/libraries/RafflErrors.sol";

import { Common } from "../utils/Common.sol";
import { ERC20Mock } from "../mocks/ERC20Mock.sol";
import { ERC721Mock } from "../mocks/ERC721Mock.sol";

contract RafflFactoryEdgeCasesTest is Common {
    Raffl raffl;

    function setUp() public virtual {
        fundAndSetPrizes(raffleCreator);
    }

    /*//////////////////////////////////////////////////////////////
                        CONCURRENT RAFFLES TESTS
    //////////////////////////////////////////////////////////////*/

    /// @dev Should handle multiple concurrent raffles
    function test_MultipleConcurrentRaffles() public {
        // Create multiple raffles
        Raffl[] memory raffles = new Raffl[](5);

        for (uint256 i = 0; i < 5; i++) {
            // Deploy new prizes for each raffle
            ERC20Mock newToken = new ERC20Mock();
            newToken.mint(raffleCreator, 100 ether);

            vm.startPrank(raffleCreator);
            newToken.approve(address(rafflFactory), 100 ether);

            IRaffl.Prize[] memory newPrizes = new IRaffl.Prize[](1);
            newPrizes[0] = IRaffl.Prize(address(newToken), IRaffl.AssetType.ERC20, 100 ether);

            raffles[i] = Raffl(
                rafflFactory.createRaffle(
                    address(0),
                    ENTRY_PRICE,
                    MIN_ENTRIES,
                    block.timestamp + DEADLINE_FROM_NOW + (i * 1 hours),
                    newPrizes,
                    tokenGates,
                    extraRecipient
                )
            );
            vm.stopPrank();
        }

        // Verify all raffles are active
        RafflFactory.ActiveRaffle[] memory activeRaffles = rafflFactory.activeRaffles();
        assertEq(activeRaffles.length, 5);

        // All should be valid raffles
        for (uint256 i = 0; i < 5; i++) {
            assertTrue(rafflFactory.isRaffle(address(raffles[i])));
        }
    }

    /// @dev Should correctly process concurrent raffles at different deadlines
    function test_ProcessConcurrentRafflesAtDifferentDeadlines() public {
        // Create 3 raffles with different deadlines
        ERC20Mock token1 = new ERC20Mock();
        ERC20Mock token2 = new ERC20Mock();
        ERC20Mock token3 = new ERC20Mock();

        token1.mint(raffleCreator, 100 ether);
        token2.mint(raffleCreator, 100 ether);
        token3.mint(raffleCreator, 100 ether);

        vm.startPrank(raffleCreator);
        token1.approve(address(rafflFactory), 100 ether);
        token2.approve(address(rafflFactory), 100 ether);
        token3.approve(address(rafflFactory), 100 ether);

        IRaffl.Prize[] memory prizes1 = new IRaffl.Prize[](1);
        prizes1[0] = IRaffl.Prize(address(token1), IRaffl.AssetType.ERC20, 100 ether);

        IRaffl.Prize[] memory prizes2 = new IRaffl.Prize[](1);
        prizes2[0] = IRaffl.Prize(address(token2), IRaffl.AssetType.ERC20, 100 ether);

        IRaffl.Prize[] memory prizes3 = new IRaffl.Prize[](1);
        prizes3[0] = IRaffl.Prize(address(token3), IRaffl.AssetType.ERC20, 100 ether);

        Raffl raffl1 = Raffl(
            rafflFactory.createRaffle(
                address(0), ENTRY_PRICE, MIN_ENTRIES, block.timestamp + 1 days, prizes1, tokenGates, extraRecipient
            )
        );

        Raffl raffl2 = Raffl(
            rafflFactory.createRaffle(
                address(0), ENTRY_PRICE, MIN_ENTRIES, block.timestamp + 2 days, prizes2, tokenGates, extraRecipient
            )
        );

        Raffl raffl3 = Raffl(
            rafflFactory.createRaffle(
                address(0), ENTRY_PRICE, MIN_ENTRIES, block.timestamp + 3 days, prizes3, tokenGates, extraRecipient
            )
        );
        vm.stopPrank();

        // Buy entries for all
        makeUserBuyEntries(raffl1, userA, MIN_ENTRIES);
        makeUserBuyEntries(raffl2, userB, MIN_ENTRIES);
        makeUserBuyEntries(raffl3, userC, MIN_ENTRIES);

        // Process first raffle
        vm.warp(block.timestamp + 1 days);
        uint256 requestId1 = performUpkeepOnActiveRaffl(raffl1);

        // Second and third still active, first still in active (waiting for dispersal)
        assertEq(rafflFactory.activeRaffles().length, 3);

        // Fulfill first
        fullfillVRFOnActiveAndEligibleRaffle(requestId1, address(rafflFactory));
        assertEq(rafflFactory.activeRaffles().length, 2);

        // Process second
        vm.warp(block.timestamp + 1 days);
        uint256 requestId2 = performUpkeepOnActiveRaffl(raffl2);
        fullfillVRFOnActiveAndEligibleRaffle(requestId2, address(rafflFactory));
        assertEq(rafflFactory.activeRaffles().length, 1);

        // Process third
        vm.warp(block.timestamp + 1 days);
        uint256 requestId3 = performUpkeepOnActiveRaffl(raffl3);
        fullfillVRFOnActiveAndEligibleRaffle(requestId3, address(rafflFactory));
        assertEq(rafflFactory.activeRaffles().length, 0);
    }

    /*//////////////////////////////////////////////////////////////
                        RAFFLE CREATION VALIDATION
    //////////////////////////////////////////////////////////////*/

    /// @dev Should revert when creating raffle with past deadline
    function test_RevertIf_PastDeadline() public {
        vm.expectRevert(Errors.DeadlineIsNotFuture.selector);
        vm.prank(raffleCreator);
        rafflFactory.createRaffle(
            address(0), ENTRY_PRICE, MIN_ENTRIES, block.timestamp - 1, prizes, tokenGates, extraRecipient
        );
    }

    /// @dev Should revert when creating raffle with current timestamp as deadline
    function test_RevertIf_CurrentTimestampDeadline() public {
        vm.expectRevert(Errors.DeadlineIsNotFuture.selector);
        vm.prank(raffleCreator);
        rafflFactory.createRaffle(
            address(0), ENTRY_PRICE, MIN_ENTRIES, block.timestamp, prizes, tokenGates, extraRecipient
        );
    }

    /// @dev Should revert when creating raffle with no prizes
    function test_RevertIf_NoPrizes() public {
        IRaffl.Prize[] memory emptyPrizes = new IRaffl.Prize[](0);

        vm.expectRevert(Errors.NoPrizesProvided.selector);
        vm.prank(raffleCreator);
        rafflFactory.createRaffle(
            address(0),
            ENTRY_PRICE,
            MIN_ENTRIES,
            block.timestamp + DEADLINE_FROM_NOW,
            emptyPrizes,
            tokenGates,
            extraRecipient
        );
    }

    /// @dev Should revert when ERC20 prize has zero value
    function test_RevertIf_ERC20PrizeZeroValue() public {
        ERC20Mock token = new ERC20Mock();
        token.mint(raffleCreator, 100 ether);

        vm.startPrank(raffleCreator);
        token.approve(address(rafflFactory), 100 ether);

        IRaffl.Prize[] memory zeroPrizes = new IRaffl.Prize[](1);
        zeroPrizes[0] = IRaffl.Prize(address(token), IRaffl.AssetType.ERC20, 0);

        vm.expectRevert(Errors.ERC20PrizeAmountIsZero.selector);
        rafflFactory.createRaffle(
            address(0),
            ENTRY_PRICE,
            MIN_ENTRIES,
            block.timestamp + DEADLINE_FROM_NOW,
            zeroPrizes,
            tokenGates,
            extraRecipient
        );
        vm.stopPrank();
    }

    /// @dev Should revert when prize transfer fails (not approved)
    function test_RevertIf_PrizeNotApproved() public {
        ERC20Mock token = new ERC20Mock();
        token.mint(raffleCreator, 100 ether);
        // Note: Not approved

        IRaffl.Prize[] memory unapprovedPrizes = new IRaffl.Prize[](1);
        unapprovedPrizes[0] = IRaffl.Prize(address(token), IRaffl.AssetType.ERC20, 100 ether);

        vm.expectRevert(Errors.UnsuccessfulTransferFromPrize.selector);
        vm.prank(raffleCreator);
        rafflFactory.createRaffle(
            address(0),
            ENTRY_PRICE,
            MIN_ENTRIES,
            block.timestamp + DEADLINE_FROM_NOW,
            unapprovedPrizes,
            tokenGates,
            extraRecipient
        );
    }

    /*//////////////////////////////////////////////////////////////
                        ACTIVE RAFFLES MANAGEMENT
    //////////////////////////////////////////////////////////////*/

    /// @dev Should correctly add and remove raffles from active list
    function test_ActiveRafflesManagement() public {
        assertEq(rafflFactory.activeRaffles().length, 0);

        // Create raffle
        raffl = createNewRaffle(raffleCreator);
        assertEq(rafflFactory.activeRaffles().length, 1);

        // Buy entries
        makeUserBuyEntries(raffl, userA, MIN_ENTRIES);

        // Process and complete
        vm.warp(raffl.deadline());
        uint256 requestId = performUpkeepOnActiveRaffl(raffl);
        fullfillVRFOnActiveAndEligibleRaffle(requestId, address(rafflFactory));

        // Should be removed after dispersal
        assertEq(rafflFactory.activeRaffles().length, 0);
    }

    /// @dev Should correctly manage active raffles when some fail
    function test_ActiveRafflesWithFailedRaffles() public {
        // Create 3 raffles
        ERC20Mock token1 = new ERC20Mock();
        ERC20Mock token2 = new ERC20Mock();
        ERC20Mock token3 = new ERC20Mock();

        token1.mint(raffleCreator, 100 ether);
        token2.mint(raffleCreator, 100 ether);
        token3.mint(raffleCreator, 100 ether);

        vm.startPrank(raffleCreator);
        token1.approve(address(rafflFactory), 100 ether);
        token2.approve(address(rafflFactory), 100 ether);
        token3.approve(address(rafflFactory), 100 ether);

        IRaffl.Prize[] memory p1 = new IRaffl.Prize[](1);
        p1[0] = IRaffl.Prize(address(token1), IRaffl.AssetType.ERC20, 100 ether);

        IRaffl.Prize[] memory p2 = new IRaffl.Prize[](1);
        p2[0] = IRaffl.Prize(address(token2), IRaffl.AssetType.ERC20, 100 ether);

        IRaffl.Prize[] memory p3 = new IRaffl.Prize[](1);
        p3[0] = IRaffl.Prize(address(token3), IRaffl.AssetType.ERC20, 100 ether);

        Raffl raffl1 = Raffl(
            rafflFactory.createRaffle(
                address(0), ENTRY_PRICE, MIN_ENTRIES, block.timestamp + 1 days, p1, tokenGates, extraRecipient
            )
        );

        Raffl raffl2 = Raffl(
            rafflFactory.createRaffle(
                address(0), ENTRY_PRICE, MIN_ENTRIES, block.timestamp + 1 days, p2, tokenGates, extraRecipient
            )
        );

        Raffl raffl3 = Raffl(
            rafflFactory.createRaffle(
                address(0), ENTRY_PRICE, MIN_ENTRIES, block.timestamp + 1 days, p3, tokenGates, extraRecipient
            )
        );
        vm.stopPrank();

        assertEq(rafflFactory.activeRaffles().length, 3);

        // Only raffl2 meets criteria
        makeUserBuyEntries(raffl1, userA, 1); // Fails
        makeUserBuyEntries(raffl2, userB, MIN_ENTRIES); // Succeeds
        makeUserBuyEntries(raffl3, userC, 1); // Fails

        vm.warp(block.timestamp + 1 days);

        // Process all three
        performUpkeepOnActiveRaffl(raffl1);
        assertEq(rafflFactory.activeRaffles().length, 2); // raffl1 removed (failed)

        uint256 requestId2 = performUpkeepOnActiveRaffl(raffl2);
        assertEq(rafflFactory.activeRaffles().length, 2); // raffl2 still active (waiting for VRF)

        performUpkeepOnActiveRaffl(raffl3);
        assertEq(rafflFactory.activeRaffles().length, 1); // raffl3 removed (failed)

        // Complete raffl2
        fullfillVRFOnActiveAndEligibleRaffle(requestId2, address(rafflFactory));
        assertEq(rafflFactory.activeRaffles().length, 0);

        // Verify states
        assertEq(uint8(raffl1.gameStatus()), uint8(IRaffl.GameStatus.FailedDraw));
        assertEq(uint8(raffl2.gameStatus()), uint8(IRaffl.GameStatus.SuccessDraw));
        assertEq(uint8(raffl3.gameStatus()), uint8(IRaffl.GameStatus.FailedDraw));
    }

    /*//////////////////////////////////////////////////////////////
                        SALT AND DETERMINISTIC DEPLOYMENT
    //////////////////////////////////////////////////////////////*/

    /// @dev Should use different salts for each deployment
    function test_DifferentSaltsPerDeployment() public {
        address[] memory addresses = new address[](3);

        for (uint256 i = 0; i < 3; i++) {
            ERC20Mock token = new ERC20Mock();
            token.mint(raffleCreator, 100 ether);

            vm.startPrank(raffleCreator);
            token.approve(address(rafflFactory), 100 ether);

            IRaffl.Prize[] memory p = new IRaffl.Prize[](1);
            p[0] = IRaffl.Prize(address(token), IRaffl.AssetType.ERC20, 100 ether);

            addresses[i] = rafflFactory.createRaffle(
                address(0),
                ENTRY_PRICE,
                MIN_ENTRIES,
                block.timestamp + DEADLINE_FROM_NOW + i,
                p,
                tokenGates,
                extraRecipient
            );
            vm.stopPrank();
        }

        // All addresses should be unique
        assertTrue(addresses[0] != addresses[1]);
        assertTrue(addresses[1] != addresses[2]);
        assertTrue(addresses[0] != addresses[2]);
    }

    /// @dev Should allow calling nextSalt publicly
    function test_NextSaltCallable() public {
        // Anyone can call nextSalt
        rafflFactory.nextSalt();
        // Just verify it doesn't revert
    }

    /*//////////////////////////////////////////////////////////////
                        CHECK UPKEEP EDGE CASES
    //////////////////////////////////////////////////////////////*/

    /// @dev Should revert checkUpkeep when no active raffles
    function test_RevertIf_CheckUpkeepNoActiveRaffles() public {
        vm.expectRevert(Errors.NoActiveRaffles.selector);
        rafflFactory.checkUpkeep(abi.encode(0, 100));
    }

    /// @dev Should revert checkUpkeep with invalid bounds
    function test_RevertIf_CheckUpkeepInvalidBounds() public {
        raffl = createNewRaffle(raffleCreator);

        // Lower >= upper
        vm.expectRevert(Errors.InvalidLowerAndUpperBounds.selector);
        rafflFactory.checkUpkeep(abi.encode(10, 5));

        vm.expectRevert(Errors.InvalidLowerAndUpperBounds.selector);
        rafflFactory.checkUpkeep(abi.encode(5, 5));
    }

    /// @dev Should correctly identify raffle needing upkeep
    function test_CheckUpkeepIdentifiesReadyRaffle() public {
        raffl = createNewRaffle(raffleCreator);
        makeUserBuyEntries(raffl, userA, MIN_ENTRIES);

        // Before deadline
        (bool upkeepNeeded,) = rafflFactory.checkUpkeep(abi.encode(0, 10));
        assertFalse(upkeepNeeded);

        // At deadline
        vm.warp(raffl.deadline());
        (upkeepNeeded,) = rafflFactory.checkUpkeep(abi.encode(0, 10));
        assertTrue(upkeepNeeded);
    }

    /*//////////////////////////////////////////////////////////////
                        PERFORM UPKEEP EDGE CASES
    //////////////////////////////////////////////////////////////*/

    /// @dev Should revert performUpkeep with invalid index
    function test_RevertIf_PerformUpkeepInvalidIndex() public {
        raffl = createNewRaffle(raffleCreator);

        vm.expectRevert(Errors.UpkeepConditionNotMet.selector);
        rafflFactory.performUpkeep(abi.encode(address(raffl), 999));
    }

    /// @dev Should revert performUpkeep with wrong raffle address
    function test_RevertIf_PerformUpkeepWrongAddress() public {
        raffl = createNewRaffle(raffleCreator);

        vm.expectRevert(Errors.UpkeepConditionNotMet.selector);
        rafflFactory.performUpkeep(abi.encode(address(0x1234), 0));
    }

    /// @dev Should revert performUpkeep before deadline
    function test_RevertIf_PerformUpkeepBeforeDeadline() public {
        raffl = createNewRaffle(raffleCreator);
        makeUserBuyEntries(raffl, userA, MIN_ENTRIES);

        vm.expectRevert(Errors.UpkeepConditionNotMet.selector);
        rafflFactory.performUpkeep(abi.encode(address(raffl), 0));
    }

    /// @dev Should revert performUpkeep if already performed
    function test_RevertIf_PerformUpkeepTwice() public {
        raffl = createNewRaffle(raffleCreator);
        makeUserBuyEntries(raffl, userA, MIN_ENTRIES);

        vm.warp(raffl.deadline());
        performUpkeepOnActiveRaffl(raffl);

        // Try again - should fail since upkeep already performed
        (address activeRaffle, uint256 activeRaffleIdx,) = findActiveRaffle(raffl);
        bytes memory performData = abi.encode(activeRaffle, activeRaffleIdx);

        vm.expectRevert(Errors.UpkeepConditionNotMet.selector);
        rafflFactory.performUpkeep(performData);
    }

    /*//////////////////////////////////////////////////////////////
                        isRaffle VIEW FUNCTION
    //////////////////////////////////////////////////////////////*/

    /// @dev Should return true for valid raffles
    function test_IsRaffleReturnsTrue() public {
        raffl = createNewRaffle(raffleCreator);
        assertTrue(rafflFactory.isRaffle(address(raffl)));
    }

    /// @dev Should return false for non-raffle addresses
    function test_IsRaffleReturnsFalse() public {
        assertFalse(rafflFactory.isRaffle(address(0)));
        assertFalse(rafflFactory.isRaffle(address(0x1234)));
        assertFalse(rafflFactory.isRaffle(address(rafflFactory)));
        assertFalse(rafflFactory.isRaffle(userA));
    }

    /*//////////////////////////////////////////////////////////////
                        CREATION FEE HANDLING
    //////////////////////////////////////////////////////////////*/

    /// @dev Should correctly process creation fee
    function test_CreationFeeProcessed() public {
        // Set creation fee
        uint64 newCreationFee = 0.1 ether;
        vm.prank(feeCollector);
        rafflFactory.scheduleGlobalCreationFee(newCreationFee);
        vm.warp(block.timestamp + 1 hours);

        uint256 feeCollectorBefore = feeCollector.balance;

        // Create raffle with fee
        raffl = createNewRaffle(raffleCreator, newCreationFee);

        // Fee should be transferred
        assertEq(feeCollector.balance - feeCollectorBefore, newCreationFee);
    }

    /// @dev Should revert if creation fee not provided
    function test_RevertIf_CreationFeeNotProvided() public {
        uint64 newCreationFee = 0.1 ether;
        vm.prank(feeCollector);
        rafflFactory.scheduleGlobalCreationFee(newCreationFee);
        vm.warp(block.timestamp + 1 hours);

        // Try to create without fee
        vm.expectRevert();
        vm.prank(raffleCreator);
        rafflFactory.createRaffle(
            address(0),
            ENTRY_PRICE,
            MIN_ENTRIES,
            block.timestamp + DEADLINE_FROM_NOW,
            prizes,
            tokenGates,
            extraRecipient
        );
    }

    /*//////////////////////////////////////////////////////////////
                        VRF SUBSCRIPTION HANDLING
    //////////////////////////////////////////////////////////////*/

    /// @dev Should allow owner to update subscription settings
    function test_OwnerCanUpdateSubscription() public {
        uint64 newSubId = 999;
        bytes32 newKeyHash = bytes32(uint256(123));
        uint32 newGasLimit = 100_000;
        uint16 newConfirmations = 5;
        bool newNativePayment = false;

        vm.prank(admin);
        rafflFactory.handleSubscription(newSubId, newKeyHash, newGasLimit, newConfirmations, newNativePayment);

        assertEq(rafflFactory.subscriptionId(), newSubId);
    }

    /// @dev Should revert when non-owner tries to update subscription
    function test_RevertIf_NonOwnerUpdatesSubscription() public {
        vm.expectRevert();
        vm.prank(attacker);
        rafflFactory.handleSubscription(999, bytes32(0), 100_000, 3, true);
    }

    /*//////////////////////////////////////////////////////////////
                        DISPERSE REWARDS FROM FACTORY
    //////////////////////////////////////////////////////////////*/

    /// @dev Should allow dispersing rewards via factory
    function test_DisperseRewardsViaFactory() public {
        raffl = createNewRaffle(raffleCreator);
        makeUserBuyEntries(raffl, userA, MIN_ENTRIES);

        vm.warp(raffl.deadline());
        uint256 requestId = performUpkeepOnActiveRaffl(raffl);

        // VRF fulfillment
        vrfCoordinator.fulfillRandomWords(requestId, address(rafflFactory));

        // Disperse via factory
        rafflFactory.disperseRewards(address(raffl));

        assertEq(uint8(raffl.gameStatus()), uint8(IRaffl.GameStatus.SuccessDraw));
    }

    /// @dev Should revert disperseRewards for invalid raffle
    function test_RevertIf_DisperseRewardsInvalidRaffle() public {
        vm.expectRevert(Errors.InvalidVRFRequest.selector);
        rafflFactory.disperseRewards(address(0x1234));
    }

    /// @dev Should revert disperseRewards if not ready
    function test_RevertIf_DisperseRewardsNotReady() public {
        raffl = createNewRaffle(raffleCreator);
        makeUserBuyEntries(raffl, userA, MIN_ENTRIES);

        // Before deadline and VRF
        vm.expectRevert(Errors.UpkeepConditionNotMet.selector);
        rafflFactory.disperseRewards(address(raffl));

        // After deadline but before VRF
        vm.warp(raffl.deadline());
        performUpkeepOnActiveRaffl(raffl);

        vm.expectRevert(Errors.UpkeepConditionNotMet.selector);
        rafflFactory.disperseRewards(address(raffl));
    }
}
