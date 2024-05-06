// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.25;

import { Raffl } from "../../../src/Raffl.sol";
import { IRaffl } from "../../../src/interfaces/IRaffl.sol";

import { Common } from "../../utils/Common.sol";

contract RafflNoRewardsTest is Common {
    Raffl raffl;

    function setUp() public virtual {
        fundAndSetPrizes(raffleCreator);

        // Create the raffle
        vm.prank(raffleCreator);
        raffl = Raffl(
            rafflFactory.createRaffle(
                address(0),
                ENTRY_PRICE,
                MIN_ENTRIES,
                block.timestamp + DEADLINE_FROM_NOW,
                new IRaffl.Prize[](0),
                tokenGates,
                extraRecipient
            )
        );

        // Purchase entries
        makeUserBuyEntries(raffl, userA, MIN_ENTRIES);

        // Forward time to deadline
        vm.warp(raffl.deadline());
    }

    /// @dev should transfer prize to winner
    function test_CanDrawWinnerWithNoRewards() public {
        // No prizes set.
        IRaffl.Prize[] memory curPrizes = raffl.getPrizes();
        assertEq(curPrizes.length, 0);

        // Perform upkeep
        if (!raffl.criteriaMet()) revert("Criteria not met.");

        uint256 requestId = performUpkeepOnActiveRaffl(raffl);

        // FulfillVRF and getWinner
        address winnerUser = fullfillVRFOnActiveAndEligibleRaffle(requestId, address(rafflFactory));
        assertEq(winnerUser, userA);
    }
}
