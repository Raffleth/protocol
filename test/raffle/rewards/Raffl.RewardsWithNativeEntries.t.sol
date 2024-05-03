// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.25;

import { Raffl } from "../../../src/Raffl.sol";

import { Common } from "../../utils/Common.sol";

contract RafflRewardsWithNativeEntriesTest is Common {
    Raffl raffl;

    address winnerUser;
    uint256 totalPool;
    uint256 initialFeeCollectorBalance;
    uint256 initialRaffleCreatorBalance;

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

        // Set balances
        totalPool = address(raffl).balance;
        initialFeeCollectorBalance = feeCollector.balance;
        initialRaffleCreatorBalance = raffleCreator.balance;

        // Perform upkeep
        if (!raffl.criteriaMet()) revert("Criteria not met.");

        uint256 requestId = performUpkeepOnActiveRaffl(raffl);

        // FulfillVRF and getWinner
        winnerUser = fullfillVRFOnActiveAndEligibleRaffle(requestId, address(rafflFactory));
    }

    /// @dev should transfer prize to winner
    function test_DispersesRewardsToWinner() public view {
        assertEq(testERC20.balanceOf(winnerUser), ERC20_AMOUNT);
        assertEq(testERC721.balanceOf(winnerUser), 1);
        assertEq(testERC721.ownerOf(ERC721_TOKEN_ID), winnerUser);
    }

    /// @dev should transfer pool to creator after fees
    function test_TransferPoolToCreatorAfterFees() public view {
        uint64 feePercentage = raffl.feeData().feePercentage;
        uint256 fee = totalPool * feePercentage / 1 ether;

        assertEq(raffleCreator.balance - initialRaffleCreatorBalance, totalPool - fee);
    }

    /// @dev should transfer fee to collector
    function test_TransferFeeToCollector() public view {
        uint64 feePercentage = raffl.feeData().feePercentage;
        uint256 fee = totalPool * feePercentage / 1 ether;

        assertEq(feeCollector.balance - initialFeeCollectorBalance, fee);
    }

    /// @dev should not let the raffle have pool balance left
    function test_IsEmptyPoolAfterDraw() public view {
        assertEq(address(raffl).balance, 0);
    }

    /// @dev should not let the raffle have prizes left
    function test_IsEmptyPrizesAfterDraw() public view {
        assertEq(testERC20.balanceOf(address(raffl)), 0);
        assertEq(testERC721.balanceOf(address(raffl)), 0);
        assertNotEq(testERC721.ownerOf(ERC721_TOKEN_ID), address(raffl));
    }
}
