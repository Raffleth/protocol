// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.25;

import { Raffl } from "../../../src/Raffl.sol";

import { Common } from "../../utils/Common.sol";
import { ERC20Mock } from "../../mocks/ERC20Mock.sol";

contract RafflExtraRecipientWithERC20EntriesTest is Common {
    Raffl raffl;

    ERC20Mock entryAsset;

    uint256 totalPool;
    uint256 initialFeeCollectorBalance;
    uint256 initialRaffleCreatorBalance;
    uint256 initialExtraRecipientBalance;

    function setUp() public virtual {
        fundAndSetPrizes(raffleCreator);

        // Set the Extra recipient
        extraRecipient.recipient = userExtraRecipient;
        extraRecipient.sharePercentage = 0.4 ether;

        // Create the raffle
        entryAsset = new ERC20Mock();

        vm.prank(raffleCreator);
        raffl = Raffl(
            rafflFactory.createRaffle(
                address(entryAsset),
                ENTRY_PRICE,
                MIN_ENTRIES,
                block.timestamp + DEADLINE_FROM_NOW,
                prizes,
                tokenGates,
                extraRecipient
            )
        );

        // Purchase entries
        makeUserBuyEntries(raffl, entryAsset, userA, 5);
        makeUserBuyEntries(raffl, entryAsset, userB, 6);
        makeUserBuyEntries(raffl, entryAsset, userC, 7);
        makeUserBuyEntries(raffl, entryAsset, userD, 8);

        // Forward time to deadline
        vm.warp(raffl.deadline());

        // Set balances
        totalPool = entryAsset.balanceOf(address(raffl));
        initialFeeCollectorBalance = entryAsset.balanceOf(feeCollector);
        initialRaffleCreatorBalance = entryAsset.balanceOf(raffleCreator);
        initialExtraRecipientBalance = entryAsset.balanceOf(userExtraRecipient);

        // Perform upkeep
        if (!raffl.criteriaMet()) revert("Criteria not met.");

        uint256 requestId = performUpkeepOnActiveRaffl(raffl);

        // FulfillVRF and getWinner
        fullfillVRFOnActiveAndEligibleRaffle(requestId, address(rafflFactory));
    }

    /// @dev should expose the extra recipient on state
    function test_SetExtraRecipientState() public view {
        (address extraRecipientAddress, uint256 sharePercentage) = raffl.extraRecipient();

        assertEq(extraRecipientAddress, userExtraRecipient);
        assertEq(sharePercentage, 0.4 ether);
    }

    /// @dev should transfer fee to collector
    function test_TransferFeeToCollector() public view {
        uint64 feePercentage = raffl.feeData().feePercentage;
        uint256 fee = totalPool * feePercentage / 1 ether;

        assertEq(entryAsset.balanceOf(feeCollector) - initialFeeCollectorBalance, fee);
    }

    /// @dev should transfer pool to creator and extra recipient after fees
    function test_TransferPoolToCreatorAndExtraRecipientAfterFees() public view {
        uint64 feePercentage = raffl.feeData().feePercentage;
        uint256 fee = totalPool * feePercentage / 1 ether;
        uint256 netPool = totalPool - fee;

        (address extraRecipientAddress, uint256 sharePercentage) = raffl.extraRecipient();
        uint256 extraRecipientAmount = netPool * sharePercentage / 1 ether;
        uint256 creatorAmount = netPool - extraRecipientAmount;

        assertEq(entryAsset.balanceOf(extraRecipientAddress) - initialExtraRecipientBalance, extraRecipientAmount);
        assertEq(entryAsset.balanceOf(raffleCreator) - initialRaffleCreatorBalance, creatorAmount);
    }

    /// @dev should not let the raffle have pool balance left
    function test_IsEmptyPoolAfterDraw() public view {
        assertEq(entryAsset.balanceOf(address(raffl)), 0);
    }
}
