// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.24;

import { Common } from "../utils/Common.sol";
import { RafflFactory } from "../../src/RafflFactory.sol";
import { RafflFactoryErrors } from "../../src/libraries/Errors.sol";

contract RafflFactoryDeploymentTest is Common {
    uint64 PROPOSED_FEE = 0.03 ether;
    uint64 PROPOSED_FEE_PENALITY = 0.03 ether;

    function test_RevertIf_ImplementationZeroAddress() public {
        vm.expectRevert(RafflFactoryErrors.AddressCanNotBeZero.selector);
        new RafflFactory(
            address(0),
            feeCollector,
            feePercentage,
            feePenality,
            address(vrfCoordinator),
            chainlinkKeyHash,
            chainlinkSubscriptionId
        );
    }

    function test_RevertIf_FeeCollectorZeroAddress() public {
        vm.expectRevert(RafflFactoryErrors.AddressCanNotBeZero.selector);
        new RafflFactory(
            address(implementation),
            address(0),
            feePercentage,
            feePenality,
            address(vrfCoordinator),
            chainlinkKeyHash,
            chainlinkSubscriptionId
        );
    }

    function test_RevertIf_FeeOutOfBounds() public {
        vm.expectRevert(RafflFactoryErrors.FeeOutOfRange.selector);
        new RafflFactory(
            address(implementation),
            feeCollector,
            0.051 ether,
            feePenality,
            address(vrfCoordinator),
            chainlinkKeyHash,
            chainlinkSubscriptionId
        );
    }

    function test_IsChainlinkVRFConsumer() public view {
        (,,, address[] memory consumers) = vrfCoordinator.getSubscription(chainlinkSubscriptionId);
        assertEq(address(rafflFactory), consumers[0]);
    }

    function test_AllowAnyoneToExecuteProposedFeeChange() public {
        vm.prank(feeCollector);
        rafflFactory.proposeFeeChange(PROPOSED_FEE, PROPOSED_FEE_PENALITY);

        vm.expectRevert(RafflFactoryErrors.ProposalNotReady.selector);
        vm.prank(externalUser);
        rafflFactory.executeFeeChange();

        skip(3600);

        assertNotEq(rafflFactory.feePercentage(), PROPOSED_FEE);
        assertNotEq(rafflFactory.feePenality(), PROPOSED_FEE_PENALITY);

        vm.prank(externalUser);
        rafflFactory.executeFeeChange();

        assertEq(rafflFactory.feePercentage(), PROPOSED_FEE);
        assertEq(rafflFactory.feePenality(), PROPOSED_FEE_PENALITY);

        vm.expectRevert(RafflFactoryErrors.FeeAlreadySet.selector);
        vm.prank(externalUser);
        rafflFactory.executeFeeChange();
    }
}
