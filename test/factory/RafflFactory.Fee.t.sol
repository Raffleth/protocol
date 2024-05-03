// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.25;

import { RafflFactory } from "../../src/RafflFactory.sol";
import { IFeeManager } from "../../src/interfaces/IFeeManager.sol";
import { Errors } from "../../src/libraries/RafflFactoryErrors.sol";

import { Common } from "../utils/Common.sol";

contract RafflFactoryFeeTest is Common {
    uint64 PROPOSED_FEE = 0.03 ether;
    uint64 PROPOSED_FEE_PENALITY = 0.03 ether;

    /// @dev has a max fee bound
    function test_HasMaxFeeBound() public view {
        assertEq(rafflFactory.maxFee(), 0.05 ether);
    }

    /// @dev only owner can change the fee collector
    function test_RevertIf_NonOwnerSetFeeCollector() public {
        vm.expectRevert("Only callable by owner");
        vm.prank(attacker);
        rafflFactory.setFeeCollector(attacker);
    }

    /// @dev only owner can change the fee collector
    function test_OwnerCanSetFeeCollector() public {
        vm.expectRevert(Errors.AddressCanNotBeZero.selector);
        vm.prank(admin);
        rafflFactory.setFeeCollector(address(0));

        assertEq(rafflFactory.feeCollector(), feeCollector);

        vm.prank(admin);
        rafflFactory.setFeeCollector(externalUser);
        assertEq(rafflFactory.feeCollector(), externalUser);
    }

    /// @dev only fee collector can change the fee
    function test_RevertIf_NotFeeCollectorSetsFee() public {
        vm.expectRevert(Errors.NotFeeCollector.selector);
        vm.prank(attacker);
        rafflFactory.proposeFeeChange(PROPOSED_FEE, PROPOSED_FEE_PENALITY);
    }

    /// @dev allows fee collector to propose fee change within bounds
    function test_AllowProposeFeeChangeWithinBounds() public {
        vm.expectRevert(Errors.FeeOutOfRange.selector);
        vm.prank(feeCollector);
        rafflFactory.proposeFeeChange(0.07 ether, PROPOSED_FEE_PENALITY);

        assertEq(rafflFactory.feeCollector(), feeCollector);

        IFeeManager.FeeData memory currentFee = rafflFactory.feeData();

        vm.expectRevert(Errors.FeeAlreadySet.selector);
        vm.prank(feeCollector);
        rafflFactory.proposeFeeChange(currentFee.feePercentage, currentFee.feePenality);

        assertEq(rafflFactory.feePercentage(), feePercentage);
        assertEq(rafflFactory.feePenality(), feePenality);

        vm.prank(feeCollector);
        rafflFactory.proposeFeeChange(PROPOSED_FEE, PROPOSED_FEE_PENALITY);

        assertEq(rafflFactory.feePercentage(), feePercentage);
        assertEq(rafflFactory.feePenality(), feePenality);

        RafflFactory.ProposedFee memory proposedFee = rafflFactory.proposedFee();
        assertEq(proposedFee.feePercentage, PROPOSED_FEE);
    }

    /// @dev allows anyone to execute a fee change proposal
    function test_AllowAnyoneToExecuteProposedFeeChange() public {
        vm.prank(feeCollector);
        rafflFactory.proposeFeeChange(PROPOSED_FEE, PROPOSED_FEE_PENALITY);

        vm.expectRevert(Errors.ProposalNotReady.selector);
        vm.prank(externalUser);
        rafflFactory.executeFeeChange();

        skip(3600);

        assertNotEq(rafflFactory.feePercentage(), PROPOSED_FEE);
        assertNotEq(rafflFactory.feePenality(), PROPOSED_FEE_PENALITY);

        vm.prank(externalUser);
        rafflFactory.executeFeeChange();

        assertEq(rafflFactory.feePercentage(), PROPOSED_FEE);
        assertEq(rafflFactory.feePenality(), PROPOSED_FEE_PENALITY);

        vm.expectRevert(Errors.FeeAlreadySet.selector);
        vm.prank(externalUser);
        rafflFactory.executeFeeChange();
    }
}
