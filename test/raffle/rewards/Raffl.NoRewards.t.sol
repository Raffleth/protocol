// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.33;

import { Raffl } from "../../../src/Raffl.sol";
import { IRaffl } from "../../../src/interfaces/IRaffl.sol";
import { Errors } from "../../../src/libraries/RafflFactoryErrors.sol";

import { Common } from "../../utils/Common.sol";

/// @dev Tests for raffle prize requirements
contract RafflNoRewardsTest is Common {
    function setUp() public virtual {
        fundAndSetPrizes(raffleCreator);
    }

    /// @dev should not allow creating a raffle with no prizes
    function test_RevertWhen_CreatingRaffleWithNoPrizes() public {
        vm.prank(raffleCreator);
        vm.expectRevert(Errors.NoPrizesProvided.selector);
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

    /// @dev should allow creating a raffle with minimum prizes (1 prize)
    function test_CanCreateRaffleWithSinglePrize() public {
        IRaffl.Prize[] memory singlePrize = new IRaffl.Prize[](1);
        uint256 tokenId = 9999; // Use a unique token ID
        testERC721.mint(raffleCreator, tokenId);
        
        vm.startPrank(raffleCreator);
        testERC721.approve(address(rafflFactory), tokenId);
        singlePrize[0] = IRaffl.Prize({
            asset: address(testERC721),
            assetType: IRaffl.AssetType.ERC721,
            value: tokenId
        });

        Raffl raffl = Raffl(
            rafflFactory.createRaffle(
                address(0),
                ENTRY_PRICE,
                MIN_ENTRIES,
                block.timestamp + DEADLINE_FROM_NOW,
                singlePrize,
                tokenGates,
                extraRecipient
            )
        );
        vm.stopPrank();

        IRaffl.Prize[] memory curPrizes = raffl.getPrizes();
        assertEq(curPrizes.length, 1);
    }
}
