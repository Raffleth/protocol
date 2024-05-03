// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.25;

import { Raffl } from "../../../src/Raffl.sol";
import { RafflErrors } from "../../../src/libraries/Errors.sol";

import { Common } from "../../utils/Common.sol";

contract RafflRefundCreatorWithPenaltyTest is Common {
    Raffl raffl;

    function setUp() public virtual {
        fundAndSetPrizes(raffleCreator);

        // Create the raffle
        raffl = createNewRaffle(raffleCreator);

        // Set Fee Penality
        vm.startPrank(feeCollector);
        rafflFactory.proposeFeeChange(rafflFactory.feePercentage(), 0.75 ether);
        vm.stopPrank();
        skip(3600);

        rafflFactory.executeFeeChange();

        processRaffleWithoutCriteriaMet(raffl);
    }

    /// @dev should revert if creator does not pass required penality fee to refund prizes.
    function test_RevertIf_FeePenalityNotPassed() public {
        vm.prank(raffleCreator);
        vm.expectRevert(RafflErrors.RefundPenalityRequired.selector);
        raffl.refundPrizes{ value: 0 }();
    }

    /// @dev should handle fee penalty to raffle creator on `FailedDraw` state
    function test_ShouldRefundPrizesIfPenalityFeeSent() public {
        uint256 feePenality = rafflFactory.feePenality();

        vm.deal(raffleCreator, feePenality);

        vm.startPrank(raffleCreator);
        vm.expectEmit(true, true, true, true, address(raffl));
        emit Raffl.PrizesRefunded();
        raffl.refundPrizes{ value: feePenality }();
        vm.stopPrank();
    }
}
