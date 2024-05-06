// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.25;

import { Errors } from "../../src/libraries/RafflFactoryErrors.sol";
import { IFactoryFeeManager } from "../../src/interfaces/IFactoryFeeManager.sol";

import { Common } from "../utils/Common.sol";

contract RafflFactoryPoolFeeTest is Common {
    function getRafflUserPoolFee(address underlyingTokenAddress) internal view returns (uint64 poolFeePercentage) {
        (, poolFeePercentage) = rafflFactory.poolFeeData(underlyingTokenAddress);
    }

    function test_IsPoolFeeBoundedCorrectly() external view {
        uint256 factoryMaxPoolFee = rafflFactory.maxPoolFee();
        uint256 factoryMinPoolFee = rafflFactory.minPoolFee();
        assertGt(factoryMaxPoolFee, factoryMinPoolFee);
        assertLt(factoryMinPoolFee, factoryMaxPoolFee);

        uint64 poolFeePercentage = rafflFactory.globalPoolFee();

        assertGe(poolFeePercentage, rafflFactory.minPoolFee());
        assertLe(poolFeePercentage, rafflFactory.maxPoolFee());
    }

    function test_RevertWhen_ChangePoolFeeOutOfBounds() external {
        address curFeeCollector = rafflFactory.feeCollector();
        uint64 maxFactoryPoolFee = rafflFactory.maxPoolFee();

        vm.expectRevert(Errors.FeeOutOfRange.selector);
        vm.prank(curFeeCollector);
        rafflFactory.scheduleGlobalPoolFee(maxFactoryPoolFee + 1);
    }

    function test_RevertWhen_ChangeGlobalPoolFeeAsNotOwner() external {
        // Only factory owner can change the global pool fee
        vm.expectRevert(Errors.NotFeeCollector.selector);
        vm.prank(address(321));
        rafflFactory.scheduleGlobalPoolFee(0.001 ether);
    }

    function test_ChangePoolFeePercentage() external {
        address curFeeCollector = rafflFactory.feeCollector();

        // Intent #1:
        //
        // We are going to change the global pool fee
        uint64 newGlobalPoolFeePercentage = 0.035 ether; // 3.5% fee
        vm.expectEmit(address(rafflFactory));
        emit IFactoryFeeManager.GlobalPoolFeeChange(newGlobalPoolFeePercentage);
        vm.prank(curFeeCollector);
        rafflFactory.scheduleGlobalPoolFee(newGlobalPoolFeePercentage);
        //
        // Fee percentage change will be set after 1 hour
        skip(59 minutes);
        assertNotEq(rafflFactory.globalPoolFee(), newGlobalPoolFeePercentage);
        skip(1 minutes);
        assertEq(rafflFactory.globalPoolFee(), newGlobalPoolFeePercentage);

        // Intent #2:
        //
        // We are going to change the global pool fee
        newGlobalPoolFeePercentage = 0.0225 ether; // 2.25% fee
        vm.expectEmit(address(rafflFactory));
        emit IFactoryFeeManager.GlobalPoolFeeChange(newGlobalPoolFeePercentage);
        vm.prank(curFeeCollector);
        rafflFactory.scheduleGlobalPoolFee(newGlobalPoolFeePercentage);
        //
        // Fee percentage change will be set after 1 hour
        skip(59 minutes);
        assertNotEq(rafflFactory.globalPoolFee(), newGlobalPoolFeePercentage);
        skip(1 minutes);
        assertEq(rafflFactory.globalPoolFee(), newGlobalPoolFeePercentage);
    }

    function testFuzz_CanChangePoolFeeWithinBounds(uint64 newFeePercentage) external {
        uint256 initialFactoryPoolFee = rafflFactory.globalPoolFee();
        uint256 maxFactoryPoolFee = rafflFactory.maxPoolFee();

        vm.assume(newFeePercentage > 0);
        vm.assume(newFeePercentage <= maxFactoryPoolFee);
        vm.assume(newFeePercentage != initialFactoryPoolFee);
        // FIXME: not working.
        // newFeePercentage = bound(newFeePercentage, MIN_FACTORY_TRANSFER_FEE, MAX_FACTORY_TRANSFER_FEE);

        vm.prank(rafflFactory.feeCollector());
        rafflFactory.scheduleGlobalPoolFee(newFeePercentage);

        assertNotEq(rafflFactory.globalPoolFee(), newFeePercentage);

        // Fee percentage change will be set after 1 hour
        skip(59 minutes);
        assertNotEq(rafflFactory.globalPoolFee(), newFeePercentage);
        skip(1 minutes);
        assertEq(rafflFactory.globalPoolFee(), newFeePercentage);
    }

    function test_ChangeCustomPoolFeeValue() external {
        address curFeeCollector = rafflFactory.feeCollector();

        // Intent #1:
        //
        // We are going to change the custom pool fee
        uint64 newCustomPoolFeePercentage = 0.035 ether; // 3.5% fee
        vm.expectEmit(address(rafflFactory));
        emit IFactoryFeeManager.CustomPoolFeeChange(externalUser, newCustomPoolFeePercentage);
        vm.prank(curFeeCollector);
        rafflFactory.scheduleCustomPoolFee(externalUser, newCustomPoolFeePercentage);
        //
        // Fee percentage change will be set after 1 hour
        skip(59 minutes);
        assertNotEq(getRafflUserPoolFee(externalUser), newCustomPoolFeePercentage);
        skip(1 minutes);
        assertEq(getRafflUserPoolFee(externalUser), newCustomPoolFeePercentage);

        // Intent #2:
        //
        // We are going to change the custom pool fee
        newCustomPoolFeePercentage = 0.0225 ether; // 2.25% fee
        vm.expectEmit(address(rafflFactory));
        emit IFactoryFeeManager.CustomPoolFeeChange(externalUser, newCustomPoolFeePercentage);
        vm.prank(curFeeCollector);
        rafflFactory.scheduleCustomPoolFee(externalUser, newCustomPoolFeePercentage);
        //
        // Fee percentage change will be set after 1 hour
        skip(59 minutes);
        assertNotEq(getRafflUserPoolFee(externalUser), newCustomPoolFeePercentage);
        skip(1 minutes);
        assertEq(getRafflUserPoolFee(externalUser), newCustomPoolFeePercentage);
    }

    function test_RevertWhen_ChangeCustomPoolFeeAsNotOwner() external {
        // Only factory owner can change the custom pool fee
        vm.expectRevert(Errors.NotFeeCollector.selector);
        vm.prank(address(321));
        rafflFactory.scheduleCustomPoolFee(address(66_666), 0.001 ether);
    }

    function test_ToggleCustomPoolFeeValue() external {
        address curFeeCollector = rafflFactory.feeCollector();

        address externalUser = address(42_069);
        uint64 customPoolFee = 0.0325 ether;
        vm.prank(curFeeCollector);
        rafflFactory.scheduleCustomPoolFee(externalUser, customPoolFee);

        assertEq(getRafflUserPoolFee(externalUser), rafflFactory.globalPoolFee());
        skip(1 hours);
        assertNotEq(getRafflUserPoolFee(externalUser), rafflFactory.globalPoolFee());
        assertEq(getRafflUserPoolFee(externalUser), customPoolFee);

        // Intent #1:
        //
        // We are going to disable the custom pool fee
        bool customPoolFeeEnabled = false;
        vm.expectEmit(address(rafflFactory));
        emit IFactoryFeeManager.CustomPoolFeeToggle(externalUser, customPoolFeeEnabled);
        vm.prank(curFeeCollector);
        rafflFactory.toggleCustomPoolFee(externalUser, customPoolFeeEnabled);
        //
        // Custom fee will be disabled in 1 hour
        assertNotEq(getRafflUserPoolFee(externalUser), rafflFactory.globalPoolFee());
        assertEq(getRafflUserPoolFee(externalUser), customPoolFee);
        skip(59 minutes);
        assertNotEq(getRafflUserPoolFee(externalUser), rafflFactory.globalPoolFee());
        assertEq(getRafflUserPoolFee(externalUser), customPoolFee);
        skip(1 minutes);
        assertEq(getRafflUserPoolFee(externalUser), rafflFactory.globalPoolFee());
        assertNotEq(getRafflUserPoolFee(externalUser), customPoolFee);

        // Intent #2:
        //
        // We are going to enable again the custom pool fee
        customPoolFeeEnabled = true;
        vm.expectEmit(address(rafflFactory));
        emit IFactoryFeeManager.CustomPoolFeeToggle(externalUser, customPoolFeeEnabled);
        vm.prank(curFeeCollector);
        rafflFactory.toggleCustomPoolFee(externalUser, customPoolFeeEnabled);
        //
        // Custom fee will be enabled in 1 hour
        assertEq(getRafflUserPoolFee(externalUser), rafflFactory.globalPoolFee());
        assertNotEq(getRafflUserPoolFee(externalUser), customPoolFee);
        skip(59 minutes);
        assertEq(getRafflUserPoolFee(externalUser), rafflFactory.globalPoolFee());
        assertNotEq(getRafflUserPoolFee(externalUser), customPoolFee);
        skip(1 minutes);
        assertNotEq(getRafflUserPoolFee(externalUser), rafflFactory.globalPoolFee());
        assertEq(getRafflUserPoolFee(externalUser), customPoolFee);
    }

    function test_RevertWhen_ToggleCustomPoolFeeAsNotOwner() external {
        // Only factory owner can toggle (enable/disable) the custom pool fee
        vm.expectRevert(Errors.NotFeeCollector.selector);
        vm.prank(address(321));
        rafflFactory.toggleCustomPoolFee(address(66_666), false);
    }
}
