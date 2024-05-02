// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.24;

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { IERC721 } from "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import { Initializable } from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import { VRFV2PlusClient } from "@chainlink/contracts/src/v0.8/vrf/dev/libraries/VRFV2PlusClient.sol";

import { Raffl } from "../../../src/Raffl.sol";
import { Common } from "../../utils/Common.sol";
import { ERC20Mock } from "../../mocks/ERC20Mock.sol";
import { IRaffl } from "../../../src/interfaces/IRaffl.sol";
import { RafflFactory } from "../../../src/RafflFactory.sol";
import { RafflErrors } from "../../../src/libraries/Errors.sol";
import { IFeeManager } from "../../../src/interfaces/IFeeManager.sol";
import { VRFCoordinatorV2PlusMock } from "../../mocks/VRFCoordinatorV2PlusMock.sol";

contract RafflEntriesWithERC20Test is Common {
    Raffl raffl;
    uint256 entryPrice;

    ERC20Mock entryAsset;

    function setUp() public virtual {
        fundAndSetPrizes(raffleCreator);

        entryAsset = new ERC20Mock();

        vm.prank(raffleCreator);
        raffl = Raffl(
            rafflFactory.createRaffle(
                address(entryAsset),
                ENTRY_PRICE,
                MIN_ENTRIES,
                block.timestamp + DEADLINE_FROM_NOW,
                prizes,
                tokenGates,
                extraRecipient
            )
        );
        entryPrice = raffl.entryPrice();
    }

    /// @dev should validate the value when buying entries
    function test_RevertIf_TransferEntriesFailed() public {
        vm.deal(userA, entryPrice * 5);

        vm.expectRevert(bytes("TFF"));
        vm.prank(userA);
        raffl.buyEntries(5);
    }

    /// @dev should emit `EntriesBought` event when buying entries
    function test_EmitEntriesBought() public {
        uint256 quantity = 5;
        uint256 totalAmount = entryPrice * quantity;

        deal(address(entryAsset), userA, totalAmount);


        vm.startPrank(userA);
        entryAsset.approve(address(raffl), totalAmount);
        
        vm.expectEmit(true, true, true, true, address(raffl));
        emit Raffl.EntriesBought(userA, quantity, totalAmount);
        raffl.buyEntries(quantity);
        vm.stopPrank();
    }

    /// @dev should correctly increase the `pool` and `entries` state when buying entries
    function test_IncresesPoolOnERC20EntryPurchase() public {
        uint256 initialPool = raffl.pool();
        uint256 initialEntries = raffl.entries();

        uint256 quantity = 7;
        uint256 value = entryPrice * quantity;
        makeUserBuyEntries(raffl, entryAsset, userA, quantity);

        uint256 currentPool = raffl.pool();
        assertEq(currentPool - initialPool, value);

        uint256 currentEntries = raffl.entries();
        assertEq(currentEntries - initialEntries, quantity);
    }

    /// @dev should set correctly the `entriesMap` and `userEntriesMap` when buying entries
    function test_SetERC20EntriesMapAndUserEntriesMap() public {
        uint256 lastEntry = raffl.entries();

        uint256 quantity = 7;
        makeUserBuyEntries(raffl, entryAsset, userC, quantity);

        for (uint256 i = 0; i < quantity; i++) {
            uint256 entryNumber = lastEntry + i;
            address entryOwner = raffl.entriesMap(entryNumber);
            assertEq(entryOwner, userC);
        }

        uint256 userTotalEntries = raffl.userEntriesMap(userC);
        assertEq(userTotalEntries, quantity);
    }
}
