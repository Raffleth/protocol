// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.24;

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { IERC721 } from "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import { Initializable } from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import { VRFV2PlusClient } from "@chainlink/contracts/src/v0.8/vrf/dev/libraries/VRFV2PlusClient.sol";

import { Raffl } from "../../../src/Raffl.sol";
import { Common } from "../../utils/Common.sol";
import { IRaffl } from "../../../src/interfaces/IRaffl.sol";
import { RafflFactory } from "../../../src/RafflFactory.sol";
import { IFeeManager } from "../../../src/interfaces/IFeeManager.sol";
import { RafflErrors } from "../../../src/libraries/Errors.sol";
import { VRFCoordinatorV2PlusMock } from "../../mocks/VRFCoordinatorV2PlusMock.sol";

contract RafflEntriesWithNativeTest is Common {
    Raffl raffl;
    uint256 entryPrice;

    function setUp() public virtual {
        fundAndSetPrizes(raffleCreator);

        raffl = createNewRaffle(raffleCreator);
        entryPrice = raffl.entryPrice();
    }

    /// @dev should validate the quantity when buying entries
    function test_RevertIf_ZeroQuantityEntriesPurchase() public {
        vm.deal(userA, ENTRY_PRICE * 5);

        vm.expectRevert(RafflErrors.EntryQuantityRequired.selector);
        vm.prank(userA);
        raffl.buyEntries{ value: ENTRY_PRICE * 5 }(0);
    }

    /// @dev should validate the value when buying entries
    function test_RevertIf_ZeroValueEntriesPurchase() public {
        vm.expectRevert(RafflErrors.EntriesPurchaseInvalidValue.selector);
        vm.prank(userA);
        raffl.buyEntries{ value: 0 }(5);

        vm.deal(userA, 123);

        vm.expectRevert(RafflErrors.EntriesPurchaseInvalidValue.selector);
        vm.prank(userA);
        raffl.buyEntries{ value: 123 }(5);
    }

    /// @dev should validate the value when buying entries
    function test_EmitEntriesBought() public {
        uint256 quantity = 5;
        uint256 value = entryPrice * quantity;

        vm.deal(userA, value);

        vm.expectEmit(true, true, true, true, address(raffl));
        emit Raffl.EntriesBought(userA, quantity, value);

        vm.prank(userA);
        raffl.buyEntries{ value: value }(quantity);
    }

    /// @dev should correctly increase the `pool` and `entries` state when buying entries
    function test_IncresesPoolOnEntryPurchase() public {
        uint256 initialPool = raffl.pool();
        uint256 initialEntries = raffl.entries();

        uint256 quantity = 7;
        uint256 value = entryPrice * quantity;
        makeUserBuyEntries(raffl, userA, quantity);

        uint256 currentPool = raffl.pool();
        assertEq(currentPool - initialPool, value);

        uint256 currentEntries = raffl.entries();
        assertEq(currentEntries - initialEntries, quantity);
    }

    /// @dev should set correctly the `entriesMap` and `userEntriesMap` when buying entries
    function test_SetEntriesMapAndUserEntriesMap() public {
        uint256 lastEntry = raffl.entries();

        uint256 quantity = 7;
        makeUserBuyEntries(raffl, userC, quantity);

        for (uint i = 0; i < quantity; i++) {
            uint256 entryNumber = lastEntry + i;
            address entryOwner = raffl.entriesMap(entryNumber);
            assertEq(entryOwner, userC);
            
        }

        uint256 userTotalEntries = raffl.userEntriesMap(userC);
        assertEq(userTotalEntries, quantity);

    }
}
