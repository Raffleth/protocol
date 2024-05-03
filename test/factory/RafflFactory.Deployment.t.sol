// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.25;

import { RafflFactory } from "../../src/RafflFactory.sol";
import { Errors } from "../../src/libraries/RafflFactoryErrors.sol";

import { Common } from "../utils/Common.sol";

contract RafflFactoryDeploymentTest is Common {
    uint64 PROPOSED_FEE = 0.03 ether;
    uint64 PROPOSED_FEE_PENALITY = 0.03 ether;

    /// @dev should not allow an implementation that is not a contract
    function test_RevertIf_ImplementationZeroAddress() public {
        vm.expectRevert(Errors.AddressCanNotBeZero.selector);
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

    /// @dev should not allow a 0x0 address for the fee collector
    function test_RevertIf_FeeCollectorZeroAddress() public {
        vm.expectRevert(Errors.AddressCanNotBeZero.selector);
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

    /// @dev should not allow fee beyond bounds
    function test_RevertIf_FeeOutOfBounds() public {
        vm.expectRevert(Errors.FeeOutOfRange.selector);
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

    /// @dev should be a Chainlink VRF consumer
    function test_IsChainlinkVRFConsumer() public view {
        (,,,, address[] memory consumers) = vrfCoordinator.getSubscription(chainlinkSubscriptionId);
        assertEq(address(rafflFactory), consumers[0]);
    }
}
