// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.25;

import { Raffl } from "../../../src/Raffl.sol";
import { IFeeManager } from "../../../src/interfaces/IFeeManager.sol";
import { Errors } from "../../../src/libraries/RafflFactoryErrors.sol";

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
        uint256 userAQuantity = 10 ether;
        uint256 userBQuantity = 10 ether;
        uint256 userCQuantity = 10 ether;
        uint256 userDQuantity = 10 ether;

        uint256 extraQuantity = 0;

        for (uint256 i = 0; i < 1000; i++) {
            uint256 quantity = 10 ether;
            address someUser = address(uint160(10_000 + i));
            makeUserBuyEntries(raffl, someUser, quantity);
            assertEq(raffl.balanceOf(someUser), quantity);
            extraQuantity += quantity;
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
}
