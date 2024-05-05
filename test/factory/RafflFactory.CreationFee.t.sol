// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.25;

import { RafflFactory } from "../../src/RafflFactory.sol";
import { Errors } from "../../src/libraries/RafflFactoryErrors.sol";
import { IFactoryFeeManager } from "../../src/interfaces/IFactoryFeeManager.sol";

import { Common } from "../utils/Common.sol";

contract RafflFactoryCreationFeeTest is Common {
    function getRafflUserCreationFee(address user) internal view returns (uint64 creationFee) {
        (, creationFee) = rafflFactory.creationFeeData(user);
    }

    function test_ChangeGlobalCreationFeeValue() external {
        address curFeeCollector = rafflFactory.feeCollector();

        // Intent #1:
        //
        // We are going to change the global creation fee
        uint64 newGlobalCreationFeeValue = 0.7 ether;
        vm.expectEmit(address(rafflFactory));
        emit IFactoryFeeManager.GlobalCreationFeeChange(newGlobalCreationFeeValue);
        vm.prank(curFeeCollector);
        rafflFactory.scheduleGlobalCreationFee(newGlobalCreationFeeValue);
        //
        // Fee value change will be set after 1 hour
        skip(59 minutes);
        assertNotEq(rafflFactory.globalCreationFee(), newGlobalCreationFeeValue);
        skip(1 minutes);
        assertEq(rafflFactory.globalCreationFee(), newGlobalCreationFeeValue);

        // Intent #2:
        //
        // We are going to change the global creation fee
        newGlobalCreationFeeValue = 0.06 ether;
        vm.expectEmit(address(rafflFactory));
        emit IFactoryFeeManager.GlobalCreationFeeChange(newGlobalCreationFeeValue);
        vm.prank(curFeeCollector);
        rafflFactory.scheduleGlobalCreationFee(newGlobalCreationFeeValue);
        //
        // Fee value change will be set after 1 hour
        skip(59 minutes);
        assertNotEq(rafflFactory.globalCreationFee(), newGlobalCreationFeeValue);
        skip(1 minutes);
        assertEq(rafflFactory.globalCreationFee(), newGlobalCreationFeeValue);
    }

    function test_RevertWhen_ChangeGlobalCreationFeeAsNotOwner() external {
        // Only factory owner can change the global creation fee
        vm.expectRevert(Errors.NotFeeCollector.selector);
        vm.prank(address(321));
        rafflFactory.scheduleGlobalCreationFee(0.001 ether);
    }

    function test_ChangeCustomCreationFeeValue() external {
        address curFeeCollector = rafflFactory.feeCollector();

        // Intent #1:
        //
        // We are going to change the custom creation fee
        uint64 newCustomCreationFee = 0.02 ether;
        vm.expectEmit(address(rafflFactory));
        emit IFactoryFeeManager.CustomCreationFeeChange(externalUser, newCustomCreationFee);
        vm.prank(curFeeCollector);
        rafflFactory.scheduleCustomCreationFee(externalUser, newCustomCreationFee);
        //
        // Fee value change will be set after 1 hour
        skip(59 minutes);
        assertNotEq(getRafflUserCreationFee(externalUser), newCustomCreationFee);
        skip(1 minutes);
        assertEq(getRafflUserCreationFee(externalUser), newCustomCreationFee);

        // Intent #2:
        //
        // We are going to change the custom creation fee
        newCustomCreationFee = 0.055 ether;
        vm.prank(curFeeCollector);
        rafflFactory.scheduleCustomCreationFee(externalUser, newCustomCreationFee);
        //
        // Fee value change will be set after 1 hour
        skip(59 minutes);
        assertNotEq(getRafflUserCreationFee(externalUser), newCustomCreationFee);
        skip(1 minutes);
        assertEq(getRafflUserCreationFee(externalUser), newCustomCreationFee);
    }

    function test_RevertWhen_ChangeCustomCreationFeeAsNotOwner() external {
        // Only factory owner can change the custom creation fee
        vm.expectRevert(Errors.NotFeeCollector.selector);
        vm.prank(address(321));
        rafflFactory.scheduleCustomCreationFee(address(66_666), 0.0123 ether);
    }

    function test_ToggleCustomCreationFeeValue() external {
        address curFeeCollector = rafflFactory.feeCollector();
        uint64 customCreationFee = 0.6 ether;
        vm.prank(curFeeCollector);
        rafflFactory.scheduleCustomCreationFee(externalUser, customCreationFee);

        assertEq(getRafflUserCreationFee(externalUser), rafflFactory.globalCreationFee());
        skip(1 hours);
        assertNotEq(getRafflUserCreationFee(externalUser), rafflFactory.globalCreationFee());
        assertEq(getRafflUserCreationFee(externalUser), customCreationFee);

        // Intent #1:
        //
        // We are going to disable the custom creation fee
        bool customCreationFeeEnabled = false;
        vm.expectEmit(address(rafflFactory));
        emit IFactoryFeeManager.CustomCreationFeeToggle(externalUser, customCreationFeeEnabled);
        vm.prank(curFeeCollector);
        rafflFactory.toggleCustomCreationFee(externalUser, customCreationFeeEnabled);
        //
        // Custom fee will be disabled in 1 hour
        assertNotEq(getRafflUserCreationFee(externalUser), rafflFactory.globalCreationFee());
        assertEq(getRafflUserCreationFee(externalUser), customCreationFee);
        skip(59 minutes);
        assertNotEq(getRafflUserCreationFee(externalUser), rafflFactory.globalCreationFee());
        assertEq(getRafflUserCreationFee(externalUser), customCreationFee);
        skip(1 minutes);
        assertEq(getRafflUserCreationFee(externalUser), rafflFactory.globalCreationFee());
        assertNotEq(getRafflUserCreationFee(externalUser), customCreationFee);

        // Intent #2:
        //
        // We are going to enable again the custom creation fee
        customCreationFeeEnabled = true;
        vm.expectEmit(address(rafflFactory));
        emit IFactoryFeeManager.CustomCreationFeeToggle(externalUser, customCreationFeeEnabled);
        vm.prank(curFeeCollector);
        rafflFactory.toggleCustomCreationFee(externalUser, customCreationFeeEnabled);
        //
        // Custom fee will be enabled in 1 hour
        assertEq(getRafflUserCreationFee(externalUser), rafflFactory.globalCreationFee());
        assertNotEq(getRafflUserCreationFee(externalUser), customCreationFee);
        skip(59 minutes);
        assertEq(getRafflUserCreationFee(externalUser), rafflFactory.globalCreationFee());
        assertNotEq(getRafflUserCreationFee(externalUser), customCreationFee);
        skip(1 minutes);
        assertNotEq(getRafflUserCreationFee(externalUser), rafflFactory.globalCreationFee());
        assertEq(getRafflUserCreationFee(externalUser), customCreationFee);
    }

    function test_RevertWhen_ToggleCustomCreationFeeAsNotOwner() external {
        // Only factory owner can toggle (enable/disable) the custom creation fee
        vm.expectRevert(Errors.NotFeeCollector.selector);
        vm.prank(address(321));
        rafflFactory.toggleCustomCreationFee(address(66_666), false);
    }
}
