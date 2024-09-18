// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.27;

import { Raffl } from "../../../src/Raffl.sol";
import { IFeeManager } from "../../../src/interfaces/IFeeManager.sol";
import { Errors } from "../../../src/libraries/RafflFactoryErrors.sol";

import { Common } from "../../utils/Common.sol";

contract RafflCustomCreationFeeTest is Common {
    address someUser = address(200);

    function setUp() public virtual {
        fundAndSetPrizes(someUser);
    }

    function proposeAndExecuteCreationFeeChange(address user, uint64 newCreationFee) internal {
        vm.prank(feeCollector);
        rafflFactory.scheduleCustomCreationFee(user, newCreationFee);
        skip(1 hours);
    }

    function proposeAndExecuteCreationFeeToggleOff(address user) internal {
        vm.prank(feeCollector);
        rafflFactory.toggleCustomCreationFee(user, false);
        skip(1 hours);
    }

    /// @dev should not allow creation fee change if the sender is not the fee collector
    function test_RevertIfCustomCreationFeeChangeNotByFeeCollector() public {
        uint64 newCustomCreationFee = 0.075 ether;

        vm.prank(attacker);
        vm.expectRevert(Errors.NotFeeCollector.selector);
        rafflFactory.scheduleCustomCreationFee(someUser, newCustomCreationFee);
    }

    /// @dev should not allow creation fee toggle if the sender is not the fee collector
    function test_RevertIfCustomCreationFeeToggleNotByFeeCollector() public {
        vm.prank(attacker);
        vm.expectRevert(Errors.NotFeeCollector.selector);
        rafflFactory.toggleCustomCreationFee(someUser, false);
    }

    /// @dev should not allow creation if fee not passed
    function test_RevertIfCustomCreationFeeNotPassed() public {
        uint64 newCustomCreationFee = 0.075 ether;

        proposeAndExecuteCreationFeeChange(someUser, newCustomCreationFee);

        vm.prank(someUser);
        vm.expectRevert(Errors.InsufficientCreationFee.selector);
        rafflFactory.createRaffle{ value: 0 }(
            address(0),
            ENTRY_PRICE,
            MIN_ENTRIES,
            block.timestamp + DEADLINE_FROM_NOW,
            prizes,
            tokenGates,
            extraRecipient
        );
    }

    /// @dev can set a creation fee for a specific user
    function test_CanSetCustomCreationFeePerUser() public {
        uint64 currentFactoryCreationFee = rafflFactory.globalCreationFee();
        (, uint64 currentFactoryCreationFeePerUser) = rafflFactory.creationFeeData(someUser);

        assertEq(currentFactoryCreationFee, currentFactoryCreationFeePerUser);

        uint64 newCustomCreationFee = 0.075 ether;
        assertNotEq(currentFactoryCreationFee, newCustomCreationFee);

        proposeAndExecuteCreationFeeChange(someUser, newCustomCreationFee);

        vm.deal(someUser, newCustomCreationFee);
        vm.prank(someUser);
        rafflFactory.createRaffle{ value: newCustomCreationFee }(
            address(0),
            ENTRY_PRICE,
            MIN_ENTRIES,
            block.timestamp + DEADLINE_FROM_NOW,
            prizes,
            tokenGates,
            extraRecipient
        );
    }

    /// @dev can toggle off a creation fee for a specific user (defaults to global)
    function test_CanToggleOffCustomCreationFeePerUser() public {
        uint64 globalCreationFee = rafflFactory.globalCreationFee();
        (, uint64 currentUserCreationFee) = rafflFactory.creationFeeData(someUser);
        assertEq(currentUserCreationFee, globalCreationFee);

        proposeAndExecuteCreationFeeChange(someUser, 0.02 ether);
        (, currentUserCreationFee) = rafflFactory.creationFeeData(someUser);
        assertNotEq(currentUserCreationFee, globalCreationFee);

        proposeAndExecuteCreationFeeToggleOff(someUser);
        (, currentUserCreationFee) = rafflFactory.creationFeeData(someUser);
        assertEq(globalCreationFee, currentUserCreationFee);
    }
}
