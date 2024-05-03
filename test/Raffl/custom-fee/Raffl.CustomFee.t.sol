// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.25;

import { Raffl } from "../../../src/Raffl.sol";
import { IFeeManager } from "../../../src/interfaces/IFeeManager.sol";

import { Common } from "../../utils/Common.sol";

contract RafflCustomFeeTest is Common {
    Raffl raffl;

    function setUp() public virtual {
        fundAndSetPrizes(raffleCreator);

        // Create the raffle
        raffl = createNewRaffle(raffleCreator);

        // Purchase entries
        makeUserBuyEntries(raffl, userA, 5);
        makeUserBuyEntries(raffl, userB, 6);
        makeUserBuyEntries(raffl, userC, 7);
        makeUserBuyEntries(raffl, userD, 8);

        // Forward time to deadline
        vm.warp(raffl.deadline());
    }

    /// @dev can set a custom fee for a specific raffle
    function test_CanSetCustomFeePerRaffle() public {
        IFeeManager.FeeData memory prevRafflFeeData = raffl.feeData();

        uint256 currentFactoryFee = rafflFactory.feePercentage();
        assertEq(prevRafflFeeData.feePercentage, currentFactoryFee);

        uint64 newRafflFeePercentage = 0.035 ether;
        address[] memory raffles = new address[](1);
        raffles[0] = address(raffl);

        vm.prank(feeCollector);
        rafflFactory.setRafflFee(raffles, true, newRafflFeePercentage);

        IFeeManager.FeeData memory currentRafflFeeData = raffl.feeData();
        assertEq(currentRafflFeeData.feePercentage, newRafflFeePercentage);
        /// Does the same. Just to point out that it is different.
        assertNotEq(currentRafflFeeData.feePercentage, currentFactoryFee);
    }

    /// @dev collects the changed fee from the raffle draw
    function test_TransferPoolToCreatorAfterFees() public {
        // Set a custom fee
        uint64 newRafflFeePercentage = 0.035 ether;
        address[] memory raffles = new address[](1);
        raffles[0] = address(raffl);
        vm.prank(feeCollector);
        rafflFactory.setRafflFee(raffles, true, newRafflFeePercentage);

        // Check initial balances
        uint256 initialFeeCollectorBalance = feeCollector.balance;
        uint256 initialRaffleCreatorBalance = raffleCreator.balance;

        // Get the total pool
        uint256 totalPool = address(raffl).balance;

        // Make the draw
        if (!raffl.criteriaMet()) revert("Criteria not met.");
        uint256 requestId = performUpkeepOnActiveRaffl(raffl);
        fullfillVRFOnActiveAndEligibleRaffle(requestId, address(rafflFactory));

        // Check final balances
        uint256 finalFeeCollectorBalance = feeCollector.balance;
        uint256 finalRaffleCreatorBalance = raffleCreator.balance;

        // Transfers
        uint256 creatorReceived = finalRaffleCreatorBalance - initialRaffleCreatorBalance;
        uint256 feeCollectorReceived = finalFeeCollectorBalance - initialFeeCollectorBalance;

        // Check rewards received
        uint256 expectedFeeTaken = (totalPool * newRafflFeePercentage) / 1 ether;
        assertEq(creatorReceived, totalPool - expectedFeeTaken);
        assertEq(feeCollectorReceived, expectedFeeTaken);
    }
}
