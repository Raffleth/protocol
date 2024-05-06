// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.25;

import { Raffl } from "../../../src/Raffl.sol";
import { IFeeManager } from "../../../src/interfaces/IFeeManager.sol";
import { Errors } from "../../../src/libraries/RafflFactoryErrors.sol";
import { Errors as RafflErrors } from "../../../src/libraries/RafflErrors.sol";

import { Common } from "../../utils/Common.sol";

contract RafflStressTest is Common {
    Raffl raffl;

    function setUp() public virtual {
        fundAndSetPrizes(raffleCreator);

        // Create the raffle
        raffl = createNewRaffle(raffleCreator);
    }

    /// @dev should be capable of handling large amount of users and entries
    function test_HandlesLargeAmountOfUsersAndEntries() public {
        uint256 userAQuantity = 1_000_000;
        uint256 userBQuantity = 1_000_000;
        uint256 userCQuantity = 1_000_000;
        uint256 userDQuantity = 1_000_000;

        uint256 extraQuantity = 0;

        for (uint256 i = 0; i < 1000; i++) {
            uint256 quantity = 1_000_000;
            address someUser = address(uint160(10_000 + i));
            makeUserBuyEntries(raffl, someUser, quantity);
            assertEq(raffl.balanceOf(someUser), quantity);
            extraQuantity += quantity;
        }

        for (uint256 i = 0; i < 1000; i++) {
            uint256 quantity = 1_000_000;
            address someUser = address(uint160(10_000 + i));
            assertEq(raffl.balanceOf(someUser), quantity);
        }

        makeUserBuyEntries(raffl, userA, userAQuantity);
        makeUserBuyEntries(raffl, userB, userBQuantity);
        makeUserBuyEntries(raffl, userC, userCQuantity);
        makeUserBuyEntries(raffl, userD, userDQuantity);

        assertEq(raffl.balanceOf(userA), userAQuantity);
        assertEq(raffl.balanceOf(userB), userBQuantity);
        assertEq(raffl.balanceOf(userC), userCQuantity);
        assertEq(raffl.balanceOf(userD), userDQuantity);

        assertEq(raffl.totalEntries(), userAQuantity + userBQuantity + userCQuantity + userDQuantity + extraQuantity);
    }

    /// @dev An owner cannot have more than 2**64 - 1.
    function test_RevertIf_MaximumTotalEntriesPerUserReached() public {
        uint256 maxUserSupply = (2 ** 64) - 1;
        makeUserBuyEntries(raffl, userA, maxUserSupply);

        assertEq(raffl.balanceOf(userA), maxUserSupply);
        assertEq(raffl.totalEntries(), maxUserSupply);

        uint256 entryPrice = raffl.entryPrice();
        uint256 extraQuantity = 1;
        uint256 value = entryPrice * extraQuantity;
        vm.deal(userA, value);
        vm.expectRevert(RafflErrors.MaxUserEntriesReached.selector);
        vm.prank(userA);
        raffl.buyEntries{ value: value }(extraQuantity);
    }

    /// @dev The maximum entries cannot exceed 2**256 - 1.
    /// @dev For testing purposes fake the supply of the `Raffl` entries
    function test_RevertIf_MaximumTotalEntriesReached() public {
        uint256 maxTotalSupply = (2 ** 256) - 1;

        bytes32 _currentIndexSlot = bytes32(uint256(0));

        uint256 curSupply = uint256(vm.load(address(raffl), _currentIndexSlot));
        assertEq(raffl.totalEntries(), curSupply);

        uint256 newSlotValue = maxTotalSupply;
        vm.store(address(raffl), _currentIndexSlot, bytes32(maxTotalSupply));

        assertEq(raffl.totalEntries(), newSlotValue);

        uint256 entryPrice = raffl.entryPrice();
        uint256 extraQuantity = 1;
        uint256 value = entryPrice * extraQuantity;
        vm.deal(userA, value);
        vm.prank(userA);
        vm.expectRevert(RafflErrors.MaxTotalEntriesReached.selector);
        raffl.buyEntries{ value: value }(extraQuantity);
    }
}
