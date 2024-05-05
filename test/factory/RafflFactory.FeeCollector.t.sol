// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.25;

import { RafflFactory } from "../../src/RafflFactory.sol";
import { IFeeManager } from "../../src/interfaces/IFeeManager.sol";
import { Errors } from "../../src/libraries/RafflFactoryErrors.sol";

import { Common } from "../utils/Common.sol";

contract RafflFactoryFeeTest is Common {
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
}
