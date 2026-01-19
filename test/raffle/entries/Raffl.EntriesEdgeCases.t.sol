// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.33;

import { Raffl } from "../../../src/Raffl.sol";
import { IRaffl } from "../../../src/interfaces/IRaffl.sol";
import { Errors } from "../../../src/libraries/RafflErrors.sol";

import { Common } from "../../utils/Common.sol";
import { ERC20Mock } from "../../mocks/ERC20Mock.sol";

contract RafflEntriesEdgeCasesTest is Common {
    Raffl raffl;
    uint256 entryPrice;

    function setUp() public virtual {
        fundAndSetPrizes(raffleCreator);
        raffl = createNewRaffle(raffleCreator);
        entryPrice = raffl.entryPrice();
    }

    /// @dev Helper to create a new raffle with fresh prizes
    function _createNewRaffleWithParams(
        uint256 _entryPrice,
        uint256 _minEntries,
        uint256 _deadline
    )
        internal
        returns (Raffl)
    {
        ERC20Mock newToken = new ERC20Mock();
        newToken.mint(raffleCreator, 100 ether);

        vm.startPrank(raffleCreator);
        newToken.approve(address(rafflFactory), 100 ether);

        IRaffl.Prize[] memory newPrizes = new IRaffl.Prize[](1);
        newPrizes[0] = IRaffl.Prize(address(newToken), IRaffl.AssetType.ERC20, 100 ether);

        Raffl newRaffl = Raffl(
            rafflFactory.createRaffle(
                address(0), _entryPrice, _minEntries, _deadline, newPrizes, tokenGates, extraRecipient
            )
        );
        vm.stopPrank();

        return newRaffl;
    }

    /*//////////////////////////////////////////////////////////////
                        DEADLINE BOUNDARY TESTS
    //////////////////////////////////////////////////////////////*/

    /// @dev Should allow entry purchase right before deadline
    function test_AllowsEntryOneSecondBeforeDeadline() public {
        uint256 deadline = raffl.deadline();

        // Warp to 1 second before deadline
        vm.warp(deadline - 1);

        makeUserBuyEntries(raffl, userA, 5);
        assertEq(raffl.balanceOf(userA), 5);
    }

    /// @dev Should revert entry purchase exactly at deadline
    function test_RevertIf_EntryAtExactDeadline() public {
        uint256 deadline = raffl.deadline();

        // Warp to exact deadline
        vm.warp(deadline);

        vm.deal(userA, entryPrice * 5);

        vm.expectRevert(Errors.EntriesPurchaseClosed.selector);
        vm.prank(userA);
        raffl.buyEntries{ value: entryPrice * 5 }(5);
    }

    /// @dev Should revert entry purchase after deadline
    function test_RevertIf_EntryAfterDeadline() public {
        uint256 deadline = raffl.deadline();

        // Warp past deadline
        vm.warp(deadline + 1);

        vm.deal(userA, entryPrice * 5);

        vm.expectRevert(Errors.EntriesPurchaseClosed.selector);
        vm.prank(userA);
        raffl.buyEntries{ value: entryPrice * 5 }(5);
    }

    /// @dev Should revert entry purchase long after deadline
    function test_RevertIf_EntryLongAfterDeadline() public {
        uint256 deadline = raffl.deadline();

        // Warp way past deadline (1 year)
        vm.warp(deadline + 365 days);

        vm.deal(userA, entryPrice * 5);

        vm.expectRevert(Errors.EntriesPurchaseClosed.selector);
        vm.prank(userA);
        raffl.buyEntries{ value: entryPrice * 5 }(5);
    }

    /// @dev Should correctly report deadlineExpired status
    function test_DeadlineExpiredStatus() public {
        uint256 deadline = raffl.deadline();

        // Before deadline
        assertFalse(raffl.deadlineExpired());

        // At deadline
        vm.warp(deadline);
        assertTrue(raffl.deadlineExpired());

        // After deadline
        vm.warp(deadline + 1);
        assertTrue(raffl.deadlineExpired());
    }

    /*//////////////////////////////////////////////////////////////
                        MAXIMUM ENTRIES TESTS
    //////////////////////////////////////////////////////////////*/

    /// @dev Should allow purchasing up to MAX_ENTRIES_PER_USER
    function test_AllowsMaxEntriesPerUser() public {
        Raffl lowPriceRaffl = _createNewRaffleWithParams(1 wei, 1, block.timestamp + DEADLINE_FROM_NOW);

        // MAX_ENTRIES_PER_USER is 2^64 - 1, but we'll test with a reasonable large number
        uint256 largeQuantity = 1_000_000;
        uint256 value = largeQuantity * 1 wei;

        vm.deal(userA, value);
        vm.prank(userA);
        lowPriceRaffl.buyEntries{ value: value }(largeQuantity);

        assertEq(lowPriceRaffl.balanceOf(userA), largeQuantity);
    }

    /// @dev Should revert when user tries to exceed MAX_ENTRIES_PER_USER
    function test_RevertIf_ExceedMaxEntriesPerUser() public {
        Raffl freeRaffl = _createNewRaffleWithParams(1 wei, 1, block.timestamp + DEADLINE_FROM_NOW);

        // First buy a large amount
        uint64 maxEntries = type(uint64).max;
        uint256 firstBatch = uint256(maxEntries) - 10;

        vm.deal(userA, firstBatch * 1 wei);
        vm.prank(userA);
        freeRaffl.buyEntries{ value: firstBatch * 1 wei }(firstBatch);

        // Try to buy more than remaining allowance
        vm.deal(userA, 20 wei);
        vm.expectRevert(Errors.MaxUserEntriesReached.selector);
        vm.prank(userA);
        freeRaffl.buyEntries{ value: 20 wei }(20);
    }

    /// @dev Should allow multiple users to each have max entries
    function test_MultipleUsersCanHaveLargeEntries() public {
        Raffl lowPriceRaffl = _createNewRaffleWithParams(1 wei, 1, block.timestamp + DEADLINE_FROM_NOW);

        uint256 entriesPerUser = 100_000;

        // Multiple users buy large amounts
        vm.deal(userA, entriesPerUser * 1 wei);
        vm.prank(userA);
        lowPriceRaffl.buyEntries{ value: entriesPerUser * 1 wei }(entriesPerUser);

        vm.deal(userB, entriesPerUser * 1 wei);
        vm.prank(userB);
        lowPriceRaffl.buyEntries{ value: entriesPerUser * 1 wei }(entriesPerUser);

        vm.deal(userC, entriesPerUser * 1 wei);
        vm.prank(userC);
        lowPriceRaffl.buyEntries{ value: entriesPerUser * 1 wei }(entriesPerUser);

        assertEq(lowPriceRaffl.balanceOf(userA), entriesPerUser);
        assertEq(lowPriceRaffl.balanceOf(userB), entriesPerUser);
        assertEq(lowPriceRaffl.balanceOf(userC), entriesPerUser);
        assertEq(lowPriceRaffl.totalEntries(), entriesPerUser * 3);
    }

    /*//////////////////////////////////////////////////////////////
                        ENTRY QUANTITY TESTS
    //////////////////////////////////////////////////////////////*/

    /// @dev Should allow purchasing exactly 1 entry
    function test_AllowsSingleEntry() public {
        makeUserBuyEntries(raffl, userA, 1);
        assertEq(raffl.balanceOf(userA), 1);
    }

    /// @dev Should correctly track cumulative entries from multiple purchases
    function test_CumulativeEntries() public {
        makeUserBuyEntries(raffl, userA, 3);
        assertEq(raffl.balanceOf(userA), 3);

        makeUserBuyEntries(raffl, userA, 5);
        assertEq(raffl.balanceOf(userA), 8);

        makeUserBuyEntries(raffl, userA, 2);
        assertEq(raffl.balanceOf(userA), 10);
    }

    /// @dev Should correctly track total entries from multiple users
    function test_TotalEntriesMultipleUsers() public {
        makeUserBuyEntries(raffl, userA, 3);
        makeUserBuyEntries(raffl, userB, 5);
        makeUserBuyEntries(raffl, userC, 7);

        assertEq(raffl.totalEntries(), 15);
        assertEq(raffl.balanceOf(userA), 3);
        assertEq(raffl.balanceOf(userB), 5);
        assertEq(raffl.balanceOf(userC), 7);
    }

    /*//////////////////////////////////////////////////////////////
                        ENTRY VALUE TESTS
    //////////////////////////////////////////////////////////////*/

    /// @dev Should revert when sending more ETH than required
    function test_RevertIf_ExcessETHSent() public {
        uint256 quantity = 5;
        uint256 requiredValue = entryPrice * quantity;
        uint256 excessValue = requiredValue + 1 wei;

        vm.deal(userA, excessValue);

        vm.expectRevert(Errors.EntriesPurchaseInvalidValue.selector);
        vm.prank(userA);
        raffl.buyEntries{ value: excessValue }(quantity);
    }

    /// @dev Should revert when sending less ETH than required
    function test_RevertIf_InsufficientETHSent() public {
        uint256 quantity = 5;
        uint256 requiredValue = entryPrice * quantity;
        uint256 insufficientValue = requiredValue - 1 wei;

        vm.deal(userA, requiredValue);

        vm.expectRevert(Errors.EntriesPurchaseInvalidValue.selector);
        vm.prank(userA);
        raffl.buyEntries{ value: insufficientValue }(quantity);
    }

    /// @dev Should correctly accumulate pool from entries
    function test_PoolAccumulatesCorrectly() public {
        uint256 initialPool = raffl.pool();
        assertEq(initialPool, 0);

        makeUserBuyEntries(raffl, userA, 3);
        assertEq(raffl.pool(), entryPrice * 3);

        makeUserBuyEntries(raffl, userB, 5);
        assertEq(raffl.pool(), entryPrice * 8);
    }

    /*//////////////////////////////////////////////////////////////
                        ENTRY OWNERSHIP TESTS
    //////////////////////////////////////////////////////////////*/

    /// @dev Should correctly assign ownership of sequential entries
    function test_SequentialEntryOwnership() public {
        makeUserBuyEntries(raffl, userA, 3);
        makeUserBuyEntries(raffl, userB, 2);
        makeUserBuyEntries(raffl, userC, 4);

        // UserA owns entries 0, 1, 2
        assertEq(raffl.ownerOf(0), userA);
        assertEq(raffl.ownerOf(1), userA);
        assertEq(raffl.ownerOf(2), userA);

        // UserB owns entries 3, 4
        assertEq(raffl.ownerOf(3), userB);
        assertEq(raffl.ownerOf(4), userB);

        // UserC owns entries 5, 6, 7, 8
        assertEq(raffl.ownerOf(5), userC);
        assertEq(raffl.ownerOf(6), userC);
        assertEq(raffl.ownerOf(7), userC);
        assertEq(raffl.ownerOf(8), userC);
    }

    /// @dev Should correctly handle interleaved entry purchases
    function test_InterleavedEntryPurchases() public {
        makeUserBuyEntries(raffl, userA, 2); // entries 0, 1
        makeUserBuyEntries(raffl, userB, 1); // entry 2
        makeUserBuyEntries(raffl, userA, 3); // entries 3, 4, 5
        makeUserBuyEntries(raffl, userC, 2); // entries 6, 7
        makeUserBuyEntries(raffl, userB, 2); // entries 8, 9

        assertEq(raffl.balanceOf(userA), 5);
        assertEq(raffl.balanceOf(userB), 3);
        assertEq(raffl.balanceOf(userC), 2);

        assertEq(raffl.ownerOf(0), userA);
        assertEq(raffl.ownerOf(2), userB);
        assertEq(raffl.ownerOf(5), userA);
        assertEq(raffl.ownerOf(7), userC);
        assertEq(raffl.ownerOf(9), userB);
    }

    /*//////////////////////////////////////////////////////////////
                        CRITERIA MET TESTS
    //////////////////////////////////////////////////////////////*/

    /// @dev Should correctly report criteriaMet when exactly at minEntries
    function test_CriteriaMetAtExactMinEntries() public {
        uint256 minEntries = raffl.minEntries();

        // Buy exactly minEntries
        makeUserBuyEntries(raffl, userA, minEntries);

        assertTrue(raffl.criteriaMet());
        assertEq(raffl.totalEntries(), minEntries);
    }

    /// @dev Should correctly report criteriaMet when below minEntries
    function test_CriteriaNotMetBelowMinEntries() public {
        uint256 minEntries = raffl.minEntries();

        // Buy less than minEntries
        if (minEntries > 1) {
            makeUserBuyEntries(raffl, userA, minEntries - 1);
            assertFalse(raffl.criteriaMet());
        }
    }

    /// @dev Should correctly report criteriaMet when above minEntries
    function test_CriteriaMetAboveMinEntries() public {
        uint256 minEntries = raffl.minEntries();

        // Buy more than minEntries
        makeUserBuyEntries(raffl, userA, minEntries + 5);

        assertTrue(raffl.criteriaMet());
    }

    /*//////////////////////////////////////////////////////////////
                        MIN ENTRIES = 1 TESTS
    //////////////////////////////////////////////////////////////*/

    /// @dev Should work with minEntries = 1
    function test_RaffleWithMinEntriesOne() public {
        Raffl singleEntryRaffl = _createNewRaffleWithParams(ENTRY_PRICE, 1, block.timestamp + DEADLINE_FROM_NOW);

        assertFalse(singleEntryRaffl.criteriaMet());

        makeUserBuyEntries(singleEntryRaffl, userA, 1);

        assertTrue(singleEntryRaffl.criteriaMet());
    }

    /*//////////////////////////////////////////////////////////////
                        ENTRY PRICE EDGE CASES
    //////////////////////////////////////////////////////////////*/

    /// @dev Should handle very small entry price (1 wei)
    function test_VerySmallEntryPrice() public {
        Raffl smallPriceRaffl = _createNewRaffleWithParams(1 wei, MIN_ENTRIES, block.timestamp + DEADLINE_FROM_NOW);

        uint256 quantity = 100;
        vm.deal(userA, quantity * 1 wei);
        vm.prank(userA);
        smallPriceRaffl.buyEntries{ value: quantity * 1 wei }(quantity);

        assertEq(smallPriceRaffl.balanceOf(userA), quantity);
        assertEq(smallPriceRaffl.pool(), quantity * 1 wei);
    }

    /// @dev Should handle large entry price
    function test_LargeEntryPrice() public {
        uint256 largePrice = 1000 ether;

        Raffl largePriceRaffl = _createNewRaffleWithParams(largePrice, MIN_ENTRIES, block.timestamp + DEADLINE_FROM_NOW);

        uint256 quantity = 5;
        vm.deal(userA, largePrice * quantity);
        vm.prank(userA);
        largePriceRaffl.buyEntries{ value: largePrice * quantity }(quantity);

        assertEq(largePriceRaffl.balanceOf(userA), quantity);
        assertEq(largePriceRaffl.pool(), largePrice * quantity);
    }

    /*//////////////////////////////////////////////////////////////
                        FREE ENTRY EDGE CASES
    //////////////////////////////////////////////////////////////*/

    /// @dev Should allow exactly one free entry per user
    function test_ExactlyOneFreeEntryPerUser() public {
        Raffl freeRaffl = _createNewRaffleWithParams(0, MIN_ENTRIES, block.timestamp + DEADLINE_FROM_NOW);

        vm.prank(userA);
        freeRaffl.buyEntries(1);

        assertEq(freeRaffl.balanceOf(userA), 1);

        // Second attempt should fail
        vm.expectRevert(Errors.MaxUserEntriesReached.selector);
        vm.prank(userA);
        freeRaffl.buyEntries(1);
    }

    /// @dev Should ignore quantity parameter for free entries
    function test_FreeEntryIgnoresQuantity() public {
        Raffl freeRaffl = _createNewRaffleWithParams(0, MIN_ENTRIES, block.timestamp + DEADLINE_FROM_NOW);

        // Even with quantity = 100, should only get 1 entry
        vm.prank(userA);
        freeRaffl.buyEntries(100);

        assertEq(freeRaffl.balanceOf(userA), 1);
    }

    /// @dev Should keep pool at zero for free entries
    function test_FreeEntryPoolRemainsZero() public {
        Raffl freeRaffl = _createNewRaffleWithParams(0, MIN_ENTRIES, block.timestamp + DEADLINE_FROM_NOW);

        vm.prank(userA);
        freeRaffl.buyEntries(1);
        vm.prank(userB);
        freeRaffl.buyEntries(1);
        vm.prank(userC);
        freeRaffl.buyEntries(1);

        assertEq(freeRaffl.pool(), 0);
    }

    /*//////////////////////////////////////////////////////////////
                        UPKEEP PERFORMED STATE TESTS
    //////////////////////////////////////////////////////////////*/

    /// @dev Should report upkeepPerformed as false before deadline
    function test_UpkeepNotPerformedBeforeDeadline() public {
        assertFalse(raffl.upkeepPerformed());
    }

    /// @dev Should report upkeepPerformed correctly after settling
    function test_UpkeepPerformedAfterSettling() public {
        // Buy enough entries to meet criteria
        uint256 minEntries = raffl.minEntries();
        makeUserBuyEntries(raffl, userA, minEntries);

        // Warp to deadline and perform upkeep
        vm.warp(raffl.deadline());
        performUpkeepOnActiveRaffl(raffl);

        assertTrue(raffl.upkeepPerformed());
    }
}
