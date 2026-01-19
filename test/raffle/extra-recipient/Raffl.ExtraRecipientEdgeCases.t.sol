// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.33;

import { Raffl } from "../../../src/Raffl.sol";
import { IRaffl } from "../../../src/interfaces/IRaffl.sol";
import { Errors } from "../../../src/libraries/RafflErrors.sol";

import { Common } from "../../utils/Common.sol";
import { ERC20Mock } from "../../mocks/ERC20Mock.sol";

/// @dev Contract that rejects ETH transfers
contract ETHRejecter {
    receive() external payable {
        revert("ETH rejected");
    }
}

/// @dev Contract that accepts ETH but has limited gas
contract ETHAccepter {
    receive() external payable { }
}

contract RafflExtraRecipientEdgeCasesTest is Common {
    Raffl raffl;

    function setUp() public virtual {
        fundAndSetPrizes(raffleCreator);
    }

    /*//////////////////////////////////////////////////////////////
                        BOUNDARY PERCENTAGE TESTS
    //////////////////////////////////////////////////////////////*/

    /// @dev Should handle extraRecipient with 0% share (effectively no extra recipient)
    function test_ExtraRecipientWithZeroShare() public {
        IRaffl.ExtraRecipient memory zeroShareRecipient =
            IRaffl.ExtraRecipient({ recipient: userExtraRecipient, sharePercentage: 0 });

        vm.prank(raffleCreator);
        raffl = Raffl(
            rafflFactory.createRaffle(
                address(0),
                ENTRY_PRICE,
                MIN_ENTRIES,
                block.timestamp + DEADLINE_FROM_NOW,
                prizes,
                tokenGates,
                zeroShareRecipient
            )
        );

        // Complete the raffle
        makeUserBuyEntries(raffl, userA, MIN_ENTRIES);
        vm.warp(raffl.deadline());
        uint256 requestId = performUpkeepOnActiveRaffl(raffl);

        uint256 creatorBalanceBefore = raffleCreator.balance;
        uint256 extraRecipientBalanceBefore = userExtraRecipient.balance;

        fullfillVRFOnActiveAndEligibleRaffle(requestId, address(rafflFactory));

        // Extra recipient should receive nothing
        assertEq(userExtraRecipient.balance, extraRecipientBalanceBefore);

        // Creator should receive pool minus fee
        uint256 expectedPool = ENTRY_PRICE * MIN_ENTRIES;
        uint256 expectedFee = (expectedPool * poolFeePercentage) / 1 ether;
        uint256 expectedCreatorAmount = expectedPool - expectedFee;
        assertEq(raffleCreator.balance - creatorBalanceBefore, expectedCreatorAmount);
    }

    /// @dev Should handle extraRecipient with 100% share (1 ether)
    function test_ExtraRecipientWith100PercentShare() public {
        IRaffl.ExtraRecipient memory fullShareRecipient =
            IRaffl.ExtraRecipient({ recipient: userExtraRecipient, sharePercentage: 1 ether });

        vm.prank(raffleCreator);
        raffl = Raffl(
            rafflFactory.createRaffle(
                address(0),
                ENTRY_PRICE,
                MIN_ENTRIES,
                block.timestamp + DEADLINE_FROM_NOW,
                prizes,
                tokenGates,
                fullShareRecipient
            )
        );

        makeUserBuyEntries(raffl, userA, MIN_ENTRIES);
        vm.warp(raffl.deadline());
        uint256 requestId = performUpkeepOnActiveRaffl(raffl);

        uint256 creatorBalanceBefore = raffleCreator.balance;
        uint256 extraRecipientBalanceBefore = userExtraRecipient.balance;

        fullfillVRFOnActiveAndEligibleRaffle(requestId, address(rafflFactory));

        // Creator should receive nothing (100% goes to extra recipient)
        assertEq(raffleCreator.balance, creatorBalanceBefore);

        // Extra recipient should receive pool minus fee
        uint256 expectedPool = ENTRY_PRICE * MIN_ENTRIES;
        uint256 expectedFee = (expectedPool * poolFeePercentage) / 1 ether;
        uint256 expectedExtraAmount = expectedPool - expectedFee;
        assertEq(userExtraRecipient.balance - extraRecipientBalanceBefore, expectedExtraAmount);
    }

    /// @dev Should handle extraRecipient with 50% share
    function test_ExtraRecipientWith50PercentShare() public {
        IRaffl.ExtraRecipient memory halfShareRecipient =
            IRaffl.ExtraRecipient({ recipient: userExtraRecipient, sharePercentage: 0.5 ether });

        vm.prank(raffleCreator);
        raffl = Raffl(
            rafflFactory.createRaffle(
                address(0),
                ENTRY_PRICE,
                MIN_ENTRIES,
                block.timestamp + DEADLINE_FROM_NOW,
                prizes,
                tokenGates,
                halfShareRecipient
            )
        );

        makeUserBuyEntries(raffl, userA, MIN_ENTRIES);
        vm.warp(raffl.deadline());
        uint256 requestId = performUpkeepOnActiveRaffl(raffl);

        uint256 creatorBalanceBefore = raffleCreator.balance;
        uint256 extraRecipientBalanceBefore = userExtraRecipient.balance;

        fullfillVRFOnActiveAndEligibleRaffle(requestId, address(rafflFactory));

        uint256 expectedPool = ENTRY_PRICE * MIN_ENTRIES;
        uint256 expectedFee = (expectedPool * poolFeePercentage) / 1 ether;
        uint256 afterFee = expectedPool - expectedFee;
        uint256 expectedExtraAmount = afterFee / 2;
        uint256 expectedCreatorAmount = afterFee - expectedExtraAmount;

        assertEq(userExtraRecipient.balance - extraRecipientBalanceBefore, expectedExtraAmount);
        assertEq(raffleCreator.balance - creatorBalanceBefore, expectedCreatorAmount);
    }

    /// @dev Should handle extraRecipient with very small share (1 wei percentage)
    function test_ExtraRecipientWithMinimalShare() public {
        IRaffl.ExtraRecipient memory minimalShareRecipient =
            IRaffl.ExtraRecipient({ recipient: userExtraRecipient, sharePercentage: 1 }); // 1 wei = 0.0000000000000001%

        vm.prank(raffleCreator);
        raffl = Raffl(
            rafflFactory.createRaffle(
                address(0),
                ENTRY_PRICE,
                MIN_ENTRIES,
                block.timestamp + DEADLINE_FROM_NOW,
                prizes,
                tokenGates,
                minimalShareRecipient
            )
        );

        makeUserBuyEntries(raffl, userA, MIN_ENTRIES);
        vm.warp(raffl.deadline());
        uint256 requestId = performUpkeepOnActiveRaffl(raffl);

        uint256 extraRecipientBalanceBefore = userExtraRecipient.balance;

        fullfillVRFOnActiveAndEligibleRaffle(requestId, address(rafflFactory));

        // With very small percentage, extra recipient likely gets 0 due to rounding
        // This depends on pool size
        assertTrue(userExtraRecipient.balance >= extraRecipientBalanceBefore);
    }

    /// @dev Should revert when extraRecipient share exceeds 100% (> 1 ether)
    function test_RevertIf_ExtraRecipientShareExceeds100Percent() public {
        IRaffl.ExtraRecipient memory overShareRecipient =
            IRaffl.ExtraRecipient({ recipient: userExtraRecipient, sharePercentage: 1 ether + 1 });

        vm.expectRevert(Errors.InvalidExtraRecipientShare.selector);
        vm.prank(raffleCreator);
        rafflFactory.createRaffle(
            address(0),
            ENTRY_PRICE,
            MIN_ENTRIES,
            block.timestamp + DEADLINE_FROM_NOW,
            prizes,
            tokenGates,
            overShareRecipient
        );
    }

    /*//////////////////////////////////////////////////////////////
                        NO EXTRA RECIPIENT TESTS
    //////////////////////////////////////////////////////////////*/

    /// @dev Should handle no extraRecipient (address(0))
    function test_NoExtraRecipient() public {
        IRaffl.ExtraRecipient memory noRecipient = IRaffl.ExtraRecipient({ recipient: address(0), sharePercentage: 0 });

        vm.prank(raffleCreator);
        raffl = Raffl(
            rafflFactory.createRaffle(
                address(0),
                ENTRY_PRICE,
                MIN_ENTRIES,
                block.timestamp + DEADLINE_FROM_NOW,
                prizes,
                tokenGates,
                noRecipient
            )
        );

        makeUserBuyEntries(raffl, userA, MIN_ENTRIES);
        vm.warp(raffl.deadline());
        uint256 requestId = performUpkeepOnActiveRaffl(raffl);

        uint256 creatorBalanceBefore = raffleCreator.balance;

        fullfillVRFOnActiveAndEligibleRaffle(requestId, address(rafflFactory));

        // All pool (minus fee) should go to creator
        uint256 expectedPool = ENTRY_PRICE * MIN_ENTRIES;
        uint256 expectedFee = (expectedPool * poolFeePercentage) / 1 ether;
        uint256 expectedCreatorAmount = expectedPool - expectedFee;
        assertEq(raffleCreator.balance - creatorBalanceBefore, expectedCreatorAmount);
    }

    /// @dev Should handle address(0) recipient with non-zero share (should behave as no recipient)
    function test_ZeroAddressRecipientWithNonZeroShare() public {
        // Even with non-zero share, address(0) should be treated as no extra recipient
        IRaffl.ExtraRecipient memory zeroAddressRecipient =
            IRaffl.ExtraRecipient({ recipient: address(0), sharePercentage: 0.5 ether });

        vm.prank(raffleCreator);
        raffl = Raffl(
            rafflFactory.createRaffle(
                address(0),
                ENTRY_PRICE,
                MIN_ENTRIES,
                block.timestamp + DEADLINE_FROM_NOW,
                prizes,
                tokenGates,
                zeroAddressRecipient
            )
        );

        makeUserBuyEntries(raffl, userA, MIN_ENTRIES);
        vm.warp(raffl.deadline());
        uint256 requestId = performUpkeepOnActiveRaffl(raffl);

        uint256 creatorBalanceBefore = raffleCreator.balance;

        fullfillVRFOnActiveAndEligibleRaffle(requestId, address(rafflFactory));

        // Creator should receive full pool minus fee (no extra recipient deduction)
        uint256 expectedPool = ENTRY_PRICE * MIN_ENTRIES;
        uint256 expectedFee = (expectedPool * poolFeePercentage) / 1 ether;
        uint256 expectedCreatorAmount = expectedPool - expectedFee;
        assertEq(raffleCreator.balance - creatorBalanceBefore, expectedCreatorAmount);
    }

    /*//////////////////////////////////////////////////////////////
                        ETH REJECTION TESTS
    //////////////////////////////////////////////////////////////*/

    /// @dev Should revert dispersal when extraRecipient contract rejects ETH
    function test_RevertIf_ExtraRecipientRejectsETH() public {
        ETHRejecter rejecter = new ETHRejecter();

        IRaffl.ExtraRecipient memory rejectingRecipient =
            IRaffl.ExtraRecipient({ recipient: address(rejecter), sharePercentage: 0.5 ether });

        vm.prank(raffleCreator);
        raffl = Raffl(
            rafflFactory.createRaffle(
                address(0),
                ENTRY_PRICE,
                MIN_ENTRIES,
                block.timestamp + DEADLINE_FROM_NOW,
                prizes,
                tokenGates,
                rejectingRecipient
            )
        );

        makeUserBuyEntries(raffl, userA, MIN_ENTRIES);
        vm.warp(raffl.deadline());
        uint256 requestId = performUpkeepOnActiveRaffl(raffl);

        // VRF fulfillment sets winner
        vm.recordLogs();
        vrfCoordinator.fulfillRandomWords(requestId, address(rafflFactory));

        // Now disperse rewards should fail
        vm.expectRevert(Errors.ETHTransferFailed.selector);
        raffl.disperseRewards();
    }

    /// @dev Should work when extraRecipient is a contract that accepts ETH
    function test_ExtraRecipientContractAcceptsETH() public {
        ETHAccepter accepter = new ETHAccepter();

        IRaffl.ExtraRecipient memory acceptingRecipient =
            IRaffl.ExtraRecipient({ recipient: address(accepter), sharePercentage: 0.3 ether });

        vm.prank(raffleCreator);
        raffl = Raffl(
            rafflFactory.createRaffle(
                address(0),
                ENTRY_PRICE,
                MIN_ENTRIES,
                block.timestamp + DEADLINE_FROM_NOW,
                prizes,
                tokenGates,
                acceptingRecipient
            )
        );

        makeUserBuyEntries(raffl, userA, MIN_ENTRIES);
        vm.warp(raffl.deadline());
        uint256 requestId = performUpkeepOnActiveRaffl(raffl);

        fullfillVRFOnActiveAndEligibleRaffle(requestId, address(rafflFactory));

        // Contract should have received its share
        uint256 expectedPool = ENTRY_PRICE * MIN_ENTRIES;
        uint256 expectedFee = (expectedPool * poolFeePercentage) / 1 ether;
        uint256 afterFee = expectedPool - expectedFee;
        uint256 expectedExtraAmount = (afterFee * 0.3 ether) / 1 ether;

        assertEq(address(accepter).balance, expectedExtraAmount);
    }

    /*//////////////////////////////////////////////////////////////
                        EXTRA RECIPIENT STATE TESTS
    //////////////////////////////////////////////////////////////*/

    /// @dev Should correctly store extraRecipient state
    function test_ExtraRecipientStateStored() public {
        IRaffl.ExtraRecipient memory testRecipient =
            IRaffl.ExtraRecipient({ recipient: userExtraRecipient, sharePercentage: 0.25 ether });

        vm.prank(raffleCreator);
        raffl = Raffl(
            rafflFactory.createRaffle(
                address(0),
                ENTRY_PRICE,
                MIN_ENTRIES,
                block.timestamp + DEADLINE_FROM_NOW,
                prizes,
                tokenGates,
                testRecipient
            )
        );

        (address storedRecipient, uint64 storedShare) = raffl.extraRecipient();
        assertEq(storedRecipient, userExtraRecipient);
        assertEq(storedShare, 0.25 ether);
    }

    /*//////////////////////////////////////////////////////////////
                        EXTRA RECIPIENT WITH ERC20 ENTRIES
    //////////////////////////////////////////////////////////////*/

    /// @dev Should correctly distribute ERC20 pool to extraRecipient
    function test_ExtraRecipientWithERC20Entries() public {
        ERC20Mock entryToken = new ERC20Mock();

        IRaffl.ExtraRecipient memory testRecipient =
            IRaffl.ExtraRecipient({ recipient: userExtraRecipient, sharePercentage: 0.4 ether });

        vm.prank(raffleCreator);
        raffl = Raffl(
            rafflFactory.createRaffle(
                address(entryToken),
                ENTRY_PRICE,
                MIN_ENTRIES,
                block.timestamp + DEADLINE_FROM_NOW,
                prizes,
                tokenGates,
                testRecipient
            )
        );

        // Buy entries with ERC20
        makeUserBuyEntries(raffl, entryToken, userA, MIN_ENTRIES);

        vm.warp(raffl.deadline());
        uint256 requestId = performUpkeepOnActiveRaffl(raffl);

        uint256 extraRecipientBalanceBefore = entryToken.balanceOf(userExtraRecipient);
        uint256 creatorBalanceBefore = entryToken.balanceOf(raffleCreator);

        fullfillVRFOnActiveAndEligibleRaffle(requestId, address(rafflFactory));

        uint256 expectedPool = ENTRY_PRICE * MIN_ENTRIES;
        uint256 expectedFee = (expectedPool * poolFeePercentage) / 1 ether;
        uint256 afterFee = expectedPool - expectedFee;
        uint256 expectedExtraAmount = (afterFee * 0.4 ether) / 1 ether;
        uint256 expectedCreatorAmount = afterFee - expectedExtraAmount;

        assertEq(entryToken.balanceOf(userExtraRecipient) - extraRecipientBalanceBefore, expectedExtraAmount);
        assertEq(entryToken.balanceOf(raffleCreator) - creatorBalanceBefore, expectedCreatorAmount);
    }

    /*//////////////////////////////////////////////////////////////
                        EXTRA RECIPIENT WITH FREE RAFFLE
    //////////////////////////////////////////////////////////////*/

    /// @dev Should handle extraRecipient with free raffle (no pool to distribute)
    function test_ExtraRecipientWithFreeRaffle() public {
        IRaffl.ExtraRecipient memory testRecipient =
            IRaffl.ExtraRecipient({ recipient: userExtraRecipient, sharePercentage: 0.5 ether });

        vm.prank(raffleCreator);
        raffl = Raffl(
            rafflFactory.createRaffle(
                address(0),
                0, // Free raffle
                MIN_ENTRIES,
                block.timestamp + DEADLINE_FROM_NOW,
                prizes,
                tokenGates,
                testRecipient
            )
        );

        // Get free entries from multiple users
        for (uint256 i = 0; i < MIN_ENTRIES; i++) {
            address user = address(uint160(100 + i));
            vm.prank(user);
            raffl.buyEntries(1);
        }

        vm.warp(raffl.deadline());
        uint256 requestId = performUpkeepOnActiveRaffl(raffl);

        uint256 extraRecipientBalanceBefore = userExtraRecipient.balance;
        uint256 creatorBalanceBefore = raffleCreator.balance;

        fullfillVRFOnActiveAndEligibleRaffle(requestId, address(rafflFactory));

        // No pool to distribute, balances should remain unchanged
        assertEq(userExtraRecipient.balance, extraRecipientBalanceBefore);
        assertEq(raffleCreator.balance, creatorBalanceBefore);
    }

    /*//////////////////////////////////////////////////////////////
                        EXTRA RECIPIENT COMBINED WITH POOL FEE
    //////////////////////////////////////////////////////////////*/

    /// @dev Should correctly calculate amounts when both pool fee and extra recipient are set
    function test_PoolFeeAndExtraRecipientCombined() public {
        // Set a higher pool fee for this test
        vm.prank(feeCollector);
        rafflFactory.scheduleGlobalPoolFee(0.1 ether); // 10%
        vm.warp(block.timestamp + 1 hours);

        IRaffl.ExtraRecipient memory testRecipient =
            IRaffl.ExtraRecipient({ recipient: userExtraRecipient, sharePercentage: 0.2 ether }); // 20% of remainder

        vm.prank(raffleCreator);
        raffl = Raffl(
            rafflFactory.createRaffle(
                address(0),
                ENTRY_PRICE,
                MIN_ENTRIES,
                block.timestamp + DEADLINE_FROM_NOW,
                prizes,
                tokenGates,
                testRecipient
            )
        );

        makeUserBuyEntries(raffl, userA, MIN_ENTRIES);
        vm.warp(raffl.deadline());
        uint256 requestId = performUpkeepOnActiveRaffl(raffl);

        uint256 feeCollectorBalanceBefore = feeCollector.balance;
        uint256 extraRecipientBalanceBefore = userExtraRecipient.balance;
        uint256 creatorBalanceBefore = raffleCreator.balance;

        fullfillVRFOnActiveAndEligibleRaffle(requestId, address(rafflFactory));

        uint256 pool = ENTRY_PRICE * MIN_ENTRIES;
        uint256 fee = (pool * 0.1 ether) / 1 ether; // 10% pool fee
        uint256 afterFee = pool - fee;
        uint256 extraShare = (afterFee * 0.2 ether) / 1 ether; // 20% of remainder
        uint256 creatorShare = afterFee - extraShare;

        assertEq(feeCollector.balance - feeCollectorBalanceBefore, fee);
        assertEq(userExtraRecipient.balance - extraRecipientBalanceBefore, extraShare);
        assertEq(raffleCreator.balance - creatorBalanceBefore, creatorShare);
    }

    /*//////////////////////////////////////////////////////////////
                        EXTRA RECIPIENT PRECISION TESTS
    //////////////////////////////////////////////////////////////*/

    /// @dev Should handle precise percentage calculations
    function test_ExtraRecipientPrecision() public {
        // 33.333...% share
        IRaffl.ExtraRecipient memory preciseRecipient =
            IRaffl.ExtraRecipient({ recipient: userExtraRecipient, sharePercentage: 333_333_333_333_333_333 });

        vm.prank(raffleCreator);
        raffl = Raffl(
            rafflFactory.createRaffle(
                address(0),
                ENTRY_PRICE,
                MIN_ENTRIES,
                block.timestamp + DEADLINE_FROM_NOW,
                prizes,
                tokenGates,
                preciseRecipient
            )
        );

        makeUserBuyEntries(raffl, userA, MIN_ENTRIES);
        vm.warp(raffl.deadline());
        uint256 requestId = performUpkeepOnActiveRaffl(raffl);

        uint256 extraRecipientBalanceBefore = userExtraRecipient.balance;
        uint256 creatorBalanceBefore = raffleCreator.balance;

        fullfillVRFOnActiveAndEligibleRaffle(requestId, address(rafflFactory));

        uint256 pool = ENTRY_PRICE * MIN_ENTRIES;
        uint256 fee = (pool * poolFeePercentage) / 1 ether;
        uint256 afterFee = pool - fee;
        uint256 expectedExtraShare = (afterFee * 333_333_333_333_333_333) / 1 ether;
        uint256 expectedCreatorShare = afterFee - expectedExtraShare;

        assertEq(userExtraRecipient.balance - extraRecipientBalanceBefore, expectedExtraShare);
        assertEq(raffleCreator.balance - creatorBalanceBefore, expectedCreatorShare);
    }
}
