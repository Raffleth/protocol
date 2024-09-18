// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.27;

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { IERC721 } from "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import { Initializable } from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";

import { Raffl } from "../../src/Raffl.sol";
import { IRaffl } from "../../src/interfaces/IRaffl.sol";
import { Errors } from "../../src/libraries/RafflFactoryErrors.sol";

import { Common } from "../utils/Common.sol";

contract RafflInitializeTest is Common {
    function setUp() public virtual {
        fundAndSetPrizes(raffleCreator);
    }

    /// @dev should only initialize once
    function test_RevertIf_Reinitializes() public {
        vm.startPrank(raffleCreator);

        address newRaffl = rafflFactory.createRaffle(
            address(0),
            ENTRY_PRICE,
            MIN_ENTRIES,
            block.timestamp + DEADLINE_FROM_NOW,
            prizes,
            tokenGates,
            extraRecipient
        );

        IRaffl.GameStatus gameStatus = Raffl(newRaffl).gameStatus();
        assertTrue(gameStatus == IRaffl.GameStatus.Initialized);

        vm.expectRevert(Initializable.InvalidInitialization.selector);
        Raffl(newRaffl).initialize(
            address(0),
            ENTRY_PRICE,
            MIN_ENTRIES,
            block.timestamp + DEADLINE_FROM_NOW,
            raffleCreator,
            prizes,
            tokenGates,
            extraRecipient
        );

        vm.stopPrank();
    }

    /// @dev should not allow to pass an expired deadline
    function test_RevertIf_ExpiredDeadline() public {
        vm.prank(raffleCreator);
        vm.expectRevert(Errors.DeadlineIsNotFuture.selector);
        rafflFactory.createRaffle(
            address(0), ENTRY_PRICE, MIN_ENTRIES, block.timestamp - 1, prizes, tokenGates, extraRecipient
        );
    }

    /// @dev should allow empty prizes
    function test_AllowsEmptyPrizes() public {
        vm.prank(raffleCreator);
        rafflFactory.createRaffle(
            address(0),
            ENTRY_PRICE,
            MIN_ENTRIES,
            block.timestamp + DEADLINE_FROM_NOW,
            new IRaffl.Prize[](0),
            tokenGates,
            extraRecipient
        );
    }

    /// @dev should not allow ERC-20 prize with no value
    function test_RevertIf_ERC20PrizeIsZero() public {
        IRaffl.Prize[] memory p = new IRaffl.Prize[](1);
        p[0] = (IRaffl.Prize(address(testERC20), IRaffl.AssetType.ERC20, 0));

        vm.prank(raffleCreator);
        vm.expectRevert(Errors.ERC20PrizeAmountIsZero.selector);
        rafflFactory.createRaffle(
            address(0), ENTRY_PRICE, MIN_ENTRIES, block.timestamp + DEADLINE_FROM_NOW, p, tokenGates, extraRecipient
        );
    }

    /// @dev should have set the right arguments
    function test_SetRightRafflState() public {
        vm.prank(raffleCreator);
        Raffl raffl = Raffl(
            rafflFactory.createRaffle(
                address(0),
                ENTRY_PRICE,
                MIN_ENTRIES,
                block.timestamp + DEADLINE_FROM_NOW,
                prizes,
                tokenGates,
                extraRecipient
            )
        );

        assertEq(raffl.entryPrice(), ENTRY_PRICE);
        assertEq(raffl.minEntries(), MIN_ENTRIES);
        assertEq(raffl.deadline(), block.timestamp + DEADLINE_FROM_NOW);
        assertEq(raffl.creator(), raffleCreator);
        assertEq(raffl.factory(), address(rafflFactory));
    }

    /// @dev should have the right prizes balances after being initialized
    function test_HasRightPrizesBalances() public {
        vm.prank(raffleCreator);
        Raffl raffl = Raffl(
            rafflFactory.createRaffle(
                address(0),
                ENTRY_PRICE,
                MIN_ENTRIES,
                block.timestamp + DEADLINE_FROM_NOW,
                prizes,
                tokenGates,
                extraRecipient
            )
        );

        // Prize #1 - ERC20
        {
            (address asset, IRaffl.AssetType assetType, uint256 value) = raffl.prizes(0);
            assertEq(asset, prizes[0].asset);
            assertTrue(assetType == prizes[0].assetType);
            assertEq(value, prizes[0].value);
            assertEq(IERC20(asset).balanceOf(address(raffl)), value);
        }
        // Prize #2 - ERC721
        {
            (address asset, IRaffl.AssetType assetType, uint256 value) = raffl.prizes(1);
            assertEq(asset, prizes[1].asset);
            assertTrue(assetType == prizes[1].assetType);
            assertEq(value, prizes[1].value);
            assertEq(IERC721(asset).balanceOf(address(raffl)), 1);
            assertEq(IERC721(asset).ownerOf(value), address(raffl));
        }
    }
}
