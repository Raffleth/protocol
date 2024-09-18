// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.27;

import { Raffl } from "../../../src/Raffl.sol";

import { Common } from "../../utils/Common.sol";

contract RafflExtraRecipientWithNativeEntriesTest is Common {
    Raffl raffl;

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
        raffl = createNewRaffle(raffleCreator);

        // Purchase entries
        makeUserBuyEntries(raffl, userA, 5);
        makeUserBuyEntries(raffl, userB, 6);
        makeUserBuyEntries(raffl, userC, 7);
        makeUserBuyEntries(raffl, userD, 8);

        // Forward time to deadline
        vm.warp(raffl.deadline());

        // Set balances
        totalPool = address(raffl).balance;
        initialFeeCollectorBalance = feeCollector.balance;
        initialRaffleCreatorBalance = raffleCreator.balance;
        initialExtraRecipientBalance = userExtraRecipient.balance;

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
        (, uint64 feePercentage) = raffl.poolFeeData();
        uint256 fee = totalPool * feePercentage / 1 ether;

        assertEq(feeCollector.balance - initialFeeCollectorBalance, fee);
    }

    /// @dev should transfer pool to creator and extra recipient after fees
    function test_TransferPoolToCreatorAndExtraRecipientAfterFees() public view {
        (, uint64 feePercentage) = raffl.poolFeeData();
        uint256 fee = totalPool * feePercentage / 1 ether;
        uint256 netPool = totalPool - fee;

        (address extraRecipientAddress, uint256 sharePercentage) = raffl.extraRecipient();
        uint256 extraRecipientAmount = netPool * sharePercentage / 1 ether;
        uint256 creatorAmount = netPool - extraRecipientAmount;

        assertEq(extraRecipientAddress.balance - initialExtraRecipientBalance, extraRecipientAmount);
        assertEq(raffleCreator.balance - initialRaffleCreatorBalance, creatorAmount);
    }

    /// @dev should not let the raffle have pool balance left
    function test_IsEmptyPoolAfterDraw() public view {
        assertEq(address(raffl).balance, 0);
    }
}
