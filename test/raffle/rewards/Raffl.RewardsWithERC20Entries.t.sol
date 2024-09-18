// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.27;

import { Raffl } from "../../../src/Raffl.sol";

import { Common } from "../../utils/Common.sol";
import { ERC20Mock } from "../../mocks/ERC20Mock.sol";

contract RafflRewardsWithERC20EntriesTest is Common {
    Raffl raffl;

    ERC20Mock entryAsset;

    address winnerUser;
    uint256 totalPool;
    uint256 initialFeeCollectorBalance;
    uint256 initialRaffleCreatorBalance;

    function setUp() public virtual {
        fundAndSetPrizes(raffleCreator);

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
        (, uint64 feePercentage) = raffl.poolFeeData();
        uint256 fee = totalPool * feePercentage / 1 ether;

        assertEq(entryAsset.balanceOf(raffleCreator) - initialRaffleCreatorBalance, totalPool - fee);
    }

    /// @dev should transfer fee to collector
    function test_TransferFeeToCollector() public view {
        (, uint64 feePercentage) = raffl.poolFeeData();
        uint256 fee = totalPool * feePercentage / 1 ether;

        assertEq(entryAsset.balanceOf(feeCollector) - initialFeeCollectorBalance, fee);
    }

    /// @dev should not let the raffle have pool balance left
    function test_IsEmptyPoolAfterDraw() public view {
        assertEq(entryAsset.balanceOf(address(raffl)), 0);
    }

    /// @dev should not let the raffle have prizes left
    function test_IsEmptyPrizesAfterDraw() public view {
        assertEq(testERC20.balanceOf(address(raffl)), 0);
        assertEq(testERC721.balanceOf(address(raffl)), 0);
        assertNotEq(testERC721.ownerOf(ERC721_TOKEN_ID), address(raffl));
    }
}
