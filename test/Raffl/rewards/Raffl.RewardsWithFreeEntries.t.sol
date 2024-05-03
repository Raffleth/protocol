// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.25;

import { Raffl } from "../../../src/Raffl.sol";
import { Common } from "../../utils/Common.sol";

contract RafflRewardsWithFreeEntriesTest is Common {
    Raffl raffl;

    address winnerUser;
    uint256 totalPool;
    uint256 initialFeeCollectorBalance;
    uint256 initialRaffleCreatorBalance;

    function setUp() public virtual {
        fundAndSetPrizes(raffleCreator);

        // Create the raffle
        vm.prank(raffleCreator);
        ENTRY_PRICE = 0;
        MIN_ENTRIES = 4;
        raffl = Raffl(
            rafflFactory.createRaffle(
                address(0), ENTRY_PRICE, MIN_ENTRIES, block.timestamp + DEADLINE_FROM_NOW, prizes, tokenGates, extraRecipient
            )
        );

        // Purchase entries
        makeUserBuyEntries(raffl, userA, 1);
        makeUserBuyEntries(raffl, userB, 1);
        makeUserBuyEntries(raffl, userC, 1);
        makeUserBuyEntries(raffl, userD, 1);

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

    /// @dev pool remains zero as there is no pool transfers
    function test_PoolRemainsZero() public view {
        assertEq(raffleCreator.balance, initialRaffleCreatorBalance);
        assertEq(feeCollector.balance, initialFeeCollectorBalance);
        assertEq(address(raffl).balance, 0);
    }
}
