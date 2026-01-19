// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.33;

import { Raffl } from "../../src/Raffl.sol";
import { IRaffl } from "../../src/interfaces/IRaffl.sol";
import { Errors } from "../../src/libraries/RafflErrors.sol";

import { Common } from "../utils/Common.sol";
import { ERC20Mock } from "../mocks/ERC20Mock.sol";

contract RafflFuzzTest is Common {
    Raffl raffl;

    function setUp() public virtual {
        fundAndSetPrizes(raffleCreator);
    }

    /*//////////////////////////////////////////////////////////////
                        ENTRY PRICE FUZZ TESTS
    //////////////////////////////////////////////////////////////*/

    /// @dev Fuzz test entry price from 1 wei to 1000 ether
    function testFuzz_EntryPriceRange(uint256 entryPrice) public {
        entryPrice = bound(entryPrice, 1 wei, 1000 ether);

        vm.prank(raffleCreator);
        raffl = Raffl(
            rafflFactory.createRaffle(
                address(0),
                entryPrice,
                MIN_ENTRIES,
                block.timestamp + DEADLINE_FROM_NOW,
                prizes,
                tokenGates,
                extraRecipient
            )
        );

        assertEq(raffl.entryPrice(), entryPrice);

        // User can buy entries at this price
        uint256 quantity = 3;
        vm.deal(userA, entryPrice * quantity);
        vm.prank(userA);
        raffl.buyEntries{ value: entryPrice * quantity }(quantity);

        assertEq(raffl.balanceOf(userA), quantity);
        assertEq(raffl.pool(), entryPrice * quantity);
    }

    /// @dev Fuzz test entry purchase quantities
    function testFuzz_EntryQuantities(uint256 quantity) public {
        quantity = bound(quantity, 1, 10_000);

        vm.prank(raffleCreator);
        raffl = Raffl(
            rafflFactory.createRaffle(
                address(0),
                1 wei, // Small price to allow large quantities
                1,
                block.timestamp + DEADLINE_FROM_NOW,
                prizes,
                tokenGates,
                extraRecipient
            )
        );

        vm.deal(userA, quantity * 1 wei);
        vm.prank(userA);
        raffl.buyEntries{ value: quantity * 1 wei }(quantity);

        assertEq(raffl.balanceOf(userA), quantity);
        assertEq(raffl.totalEntries(), quantity);
    }

    /*//////////////////////////////////////////////////////////////
                        DEADLINE FUZZ TESTS
    //////////////////////////////////////////////////////////////*/

    /// @dev Fuzz test deadline values
    function testFuzz_DeadlineValues(uint256 deadlineOffset) public {
        deadlineOffset = bound(deadlineOffset, 1 minutes, 365 days);

        vm.prank(raffleCreator);
        raffl = Raffl(
            rafflFactory.createRaffle(
                address(0),
                ENTRY_PRICE,
                MIN_ENTRIES,
                block.timestamp + deadlineOffset,
                prizes,
                tokenGates,
                extraRecipient
            )
        );

        assertEq(raffl.deadline(), block.timestamp + deadlineOffset);

        // Can buy before deadline
        makeUserBuyEntries(raffl, userA, 1);
        assertEq(raffl.balanceOf(userA), 1);

        // Cannot buy at or after deadline
        vm.warp(block.timestamp + deadlineOffset);
        assertTrue(raffl.deadlineExpired());

        vm.deal(userB, ENTRY_PRICE);
        vm.expectRevert(Errors.EntriesPurchaseClosed.selector);
        vm.prank(userB);
        raffl.buyEntries{ value: ENTRY_PRICE }(1);
    }

    /*//////////////////////////////////////////////////////////////
                        MIN ENTRIES FUZZ TESTS
    //////////////////////////////////////////////////////////////*/

    /// @dev Fuzz test minEntries values
    function testFuzz_MinEntriesValues(uint256 minEntries) public {
        minEntries = bound(minEntries, 1, 1000);

        vm.prank(raffleCreator);
        raffl = Raffl(
            rafflFactory.createRaffle(
                address(0), 1 wei, minEntries, block.timestamp + DEADLINE_FROM_NOW, prizes, tokenGates, extraRecipient
            )
        );

        assertEq(raffl.minEntries(), minEntries);

        // Below minEntries - criteria not met
        if (minEntries > 1) {
            vm.deal(userA, (minEntries - 1) * 1 wei);
            vm.prank(userA);
            raffl.buyEntries{ value: (minEntries - 1) * 1 wei }(minEntries - 1);
            assertFalse(raffl.criteriaMet());
        }

        // At minEntries - criteria met
        vm.deal(userB, 1 wei);
        vm.prank(userB);
        raffl.buyEntries{ value: 1 wei }(1);

        if (raffl.totalEntries() >= minEntries) {
            assertTrue(raffl.criteriaMet());
        }
    }

    /*//////////////////////////////////////////////////////////////
                        WINNER DISTRIBUTION FUZZ TESTS
    //////////////////////////////////////////////////////////////*/

    /// @dev Fuzz test winner selection with various random numbers
    function testFuzz_WinnerSelection(uint256 randomNumber, uint256 numParticipants) public {
        numParticipants = bound(numParticipants, 2, 50);

        vm.prank(raffleCreator);
        raffl = Raffl(
            rafflFactory.createRaffle(
                address(0), 1 wei, 1, block.timestamp + DEADLINE_FROM_NOW, prizes, tokenGates, extraRecipient
            )
        );

        // Create participants
        uint256 totalEntries = 0;
        for (uint256 i = 0; i < numParticipants; i++) {
            address participant = address(uint160(1000 + i));
            uint256 entries = (i % 10) + 1; // 1-10 entries each
            vm.deal(participant, entries * 1 wei);
            vm.prank(participant);
            raffl.buyEntries{ value: entries * 1 wei }(entries);
            totalEntries += entries;
        }

        vm.warp(raffl.deadline());
        uint256 requestId = performUpkeepOnActiveRaffl(raffl);

        // Fulfill with fuzz random number
        uint256[] memory randomWords = new uint256[](1);
        randomWords[0] = randomNumber;
        vm.prank(address(vrfCoordinator));
        vrfCoordinator.fulfillRandomWordsWithOverride(requestId, address(rafflFactory), randomWords);

        // Winner should be valid
        address winner = raffl.winner();
        assertTrue(winner != address(0));
        assertTrue(raffl.balanceOf(winner) > 0);

        // Winning entry should be correct
        uint256 winningEntry = raffl.winningEntry();
        assertEq(winningEntry, randomNumber % totalEntries);
        assertEq(raffl.ownerOf(winningEntry), winner);
    }

    /*//////////////////////////////////////////////////////////////
                        POOL FEE FUZZ TESTS
    //////////////////////////////////////////////////////////////*/

    /// @dev Fuzz test pool fee distribution
    function testFuzz_PoolFeeDistribution(uint64 feePercentage, uint256 poolSize) public {
        feePercentage = uint64(bound(feePercentage, 0, 0.1 ether)); // 0-10%
        poolSize = bound(poolSize, 1 ether, 1000 ether);

        // Set pool fee
        vm.prank(feeCollector);
        rafflFactory.scheduleGlobalPoolFee(feePercentage);
        vm.warp(block.timestamp + 1 hours);

        vm.prank(raffleCreator);
        raffl = Raffl(
            rafflFactory.createRaffle(
                address(0),
                poolSize / MIN_ENTRIES, // Entry price to achieve poolSize
                MIN_ENTRIES,
                block.timestamp + DEADLINE_FROM_NOW,
                prizes,
                tokenGates,
                extraRecipient
            )
        );

        // Buy exactly MIN_ENTRIES
        makeUserBuyEntries(raffl, userA, MIN_ENTRIES);

        uint256 actualPool = raffl.pool();
        uint256 expectedFee = (actualPool * feePercentage) / 1 ether;
        uint256 expectedCreatorAmount = actualPool - expectedFee;

        vm.warp(raffl.deadline());
        uint256 requestId = performUpkeepOnActiveRaffl(raffl);

        uint256 feeCollectorBefore = feeCollector.balance;
        uint256 creatorBefore = raffleCreator.balance;

        fullfillVRFOnActiveAndEligibleRaffle(requestId, address(rafflFactory));

        // Verify fee distribution
        assertEq(feeCollector.balance - feeCollectorBefore, expectedFee);
        assertEq(raffleCreator.balance - creatorBefore, expectedCreatorAmount);
    }

    /*//////////////////////////////////////////////////////////////
                        EXTRA RECIPIENT FUZZ TESTS
    //////////////////////////////////////////////////////////////*/

    /// @dev Fuzz test extra recipient share distribution
    function testFuzz_ExtraRecipientShare(uint64 sharePercentage) public {
        sharePercentage = uint64(bound(sharePercentage, 0, 1 ether)); // 0-100%

        IRaffl.ExtraRecipient memory recipient =
            IRaffl.ExtraRecipient({ recipient: userExtraRecipient, sharePercentage: sharePercentage });

        vm.prank(raffleCreator);
        raffl = Raffl(
            rafflFactory.createRaffle(
                address(0), ENTRY_PRICE, MIN_ENTRIES, block.timestamp + DEADLINE_FROM_NOW, prizes, tokenGates, recipient
            )
        );

        makeUserBuyEntries(raffl, userA, MIN_ENTRIES);

        uint256 pool = raffl.pool();
        uint256 fee = (pool * poolFeePercentage) / 1 ether;
        uint256 afterFee = pool - fee;
        uint256 expectedExtraAmount = (afterFee * sharePercentage) / 1 ether;
        uint256 expectedCreatorAmount = afterFee - expectedExtraAmount;

        vm.warp(raffl.deadline());
        uint256 requestId = performUpkeepOnActiveRaffl(raffl);

        uint256 extraRecipientBefore = userExtraRecipient.balance;
        uint256 creatorBefore = raffleCreator.balance;

        fullfillVRFOnActiveAndEligibleRaffle(requestId, address(rafflFactory));

        assertEq(userExtraRecipient.balance - extraRecipientBefore, expectedExtraAmount);
        assertEq(raffleCreator.balance - creatorBefore, expectedCreatorAmount);
    }

    /*//////////////////////////////////////////////////////////////
                        REFUND FUZZ TESTS
    //////////////////////////////////////////////////////////////*/

    /// @dev Fuzz test refund amounts
    function testFuzz_RefundAmounts(uint256 entryPrice, uint256 quantity) public {
        entryPrice = bound(entryPrice, 1 wei, 100 ether);
        quantity = bound(quantity, 1, 100);

        vm.prank(raffleCreator);
        raffl = Raffl(
            rafflFactory.createRaffle(
                address(0),
                entryPrice,
                quantity + 10, // minEntries higher than what user will buy
                block.timestamp + DEADLINE_FROM_NOW,
                prizes,
                tokenGates,
                extraRecipient
            )
        );

        // User buys entries
        vm.deal(userA, entryPrice * quantity);
        vm.prank(userA);
        raffl.buyEntries{ value: entryPrice * quantity }(quantity);

        // Process failed draw
        vm.warp(raffl.deadline());
        performUpkeepOnActiveRaffl(raffl);

        uint256 userBalanceBefore = userA.balance;

        // Refund
        raffl.refundEntries(userA);

        // Verify refund amount
        assertEq(userA.balance - userBalanceBefore, entryPrice * quantity);
    }

    /*//////////////////////////////////////////////////////////////
                        MULTIPLE USERS FUZZ TESTS
    //////////////////////////////////////////////////////////////*/

    /// @dev Fuzz test with multiple users buying different quantities
    function testFuzz_MultipleUserEntries(uint256 userAEntries, uint256 userBEntries, uint256 userCEntries) public {
        userAEntries = bound(userAEntries, 1, 100);
        userBEntries = bound(userBEntries, 1, 100);
        userCEntries = bound(userCEntries, 1, 100);

        uint256 minEntries = userAEntries + userBEntries + userCEntries;

        vm.prank(raffleCreator);
        raffl = Raffl(
            rafflFactory.createRaffle(
                address(0), 1 wei, minEntries, block.timestamp + DEADLINE_FROM_NOW, prizes, tokenGates, extraRecipient
            )
        );

        // Users buy entries
        vm.deal(userA, userAEntries * 1 wei);
        vm.prank(userA);
        raffl.buyEntries{ value: userAEntries * 1 wei }(userAEntries);

        vm.deal(userB, userBEntries * 1 wei);
        vm.prank(userB);
        raffl.buyEntries{ value: userBEntries * 1 wei }(userBEntries);

        vm.deal(userC, userCEntries * 1 wei);
        vm.prank(userC);
        raffl.buyEntries{ value: userCEntries * 1 wei }(userCEntries);

        // Verify totals
        assertEq(raffl.balanceOf(userA), userAEntries);
        assertEq(raffl.balanceOf(userB), userBEntries);
        assertEq(raffl.balanceOf(userC), userCEntries);
        assertEq(raffl.totalEntries(), minEntries);
        assertTrue(raffl.criteriaMet());
    }

    /*//////////////////////////////////////////////////////////////
                        ERC20 ENTRY FUZZ TESTS
    //////////////////////////////////////////////////////////////*/

    /// @dev Fuzz test ERC20 entry purchases
    function testFuzz_ERC20Entries(uint256 entryPrice, uint256 quantity) public {
        entryPrice = bound(entryPrice, 1 wei, 100 ether);
        quantity = bound(quantity, 1, 100);

        ERC20Mock entryToken = new ERC20Mock();

        vm.prank(raffleCreator);
        raffl = Raffl(
            rafflFactory.createRaffle(
                address(entryToken),
                entryPrice,
                1,
                block.timestamp + DEADLINE_FROM_NOW,
                prizes,
                tokenGates,
                extraRecipient
            )
        );

        uint256 totalCost = entryPrice * quantity;
        entryToken.mint(userA, totalCost);

        vm.startPrank(userA);
        entryToken.approve(address(raffl), totalCost);
        raffl.buyEntries(quantity);
        vm.stopPrank();

        assertEq(raffl.balanceOf(userA), quantity);
        assertEq(raffl.pool(), totalCost);
        assertEq(entryToken.balanceOf(address(raffl)), totalCost);
    }

    /*//////////////////////////////////////////////////////////////
                        TIMESTAMP BOUNDARY TESTS
    //////////////////////////////////////////////////////////////*/

    /// @dev Fuzz test behavior around deadline timestamp
    function testFuzz_DeadlineBoundary(uint256 timeDelta) public {
        timeDelta = bound(timeDelta, 0, 10);

        uint256 deadline = block.timestamp + 1 days;

        vm.prank(raffleCreator);
        raffl = Raffl(
            rafflFactory.createRaffle(address(0), ENTRY_PRICE, 1, deadline, prizes, tokenGates, extraRecipient)
        );

        // Warp to just before deadline
        vm.warp(deadline - timeDelta - 1);

        if (block.timestamp < deadline) {
            // Should be able to buy
            makeUserBuyEntries(raffl, userA, 1);
            assertEq(raffl.balanceOf(userA), 1);
        }

        // Warp to at or after deadline
        vm.warp(deadline + timeDelta);

        // Should not be able to buy
        vm.deal(userB, ENTRY_PRICE);
        vm.expectRevert(Errors.EntriesPurchaseClosed.selector);
        vm.prank(userB);
        raffl.buyEntries{ value: ENTRY_PRICE }(1);
    }

    /*//////////////////////////////////////////////////////////////
                        INVARIANT-STYLE FUZZ TESTS
    //////////////////////////////////////////////////////////////*/

    /// @dev Fuzz test that pool always equals sum of entry payments
    function testFuzz_PoolEqualsPayments(uint256 seed) public {
        // Bound seed to prevent overflow when creating user addresses
        seed = bound(seed, 1000, type(uint160).max - 100);

        vm.prank(raffleCreator);
        raffl = Raffl(
            rafflFactory.createRaffle(
                address(0), ENTRY_PRICE, 1, block.timestamp + DEADLINE_FROM_NOW, prizes, tokenGates, extraRecipient
            )
        );

        uint256 totalPaid = 0;

        // Multiple random users buy random amounts
        for (uint256 i = 0; i < 10; i++) {
            address user = address(uint160(seed + i));
            uint256 quantity = (uint256(keccak256(abi.encode(seed, i))) % 10) + 1;
            uint256 payment = quantity * ENTRY_PRICE;

            vm.deal(user, payment);
            vm.prank(user);
            raffl.buyEntries{ value: payment }(quantity);

            totalPaid += payment;
        }

        // Invariant: pool should equal total payments
        assertEq(raffl.pool(), totalPaid);
    }

    /// @dev Fuzz test that totalEntries equals sum of all user balances
    function testFuzz_TotalEntriesEqualsBalances(uint256 seed) public {
        // Bound seed to prevent overflow when creating user addresses
        seed = bound(seed, 1000, type(uint160).max - 100);

        vm.prank(raffleCreator);
        raffl = Raffl(
            rafflFactory.createRaffle(
                address(0), 1 wei, 1, block.timestamp + DEADLINE_FROM_NOW, prizes, tokenGates, extraRecipient
            )
        );

        address[] memory users = new address[](10);
        uint256 sumBalances = 0;

        for (uint256 i = 0; i < 10; i++) {
            users[i] = address(uint160(seed + i));
            uint256 quantity = (uint256(keccak256(abi.encode(seed, i))) % 10) + 1;

            vm.deal(users[i], quantity * 1 wei);
            vm.prank(users[i]);
            raffl.buyEntries{ value: quantity * 1 wei }(quantity);
        }

        // Sum all balances
        for (uint256 i = 0; i < 10; i++) {
            sumBalances += raffl.balanceOf(users[i]);
        }

        // Invariant: totalEntries should equal sum of balances
        assertEq(raffl.totalEntries(), sumBalances);
    }
}
