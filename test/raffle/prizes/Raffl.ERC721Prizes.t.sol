// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.33;

import { Raffl } from "../../../src/Raffl.sol";
import { IRaffl } from "../../../src/interfaces/IRaffl.sol";
import { Errors } from "../../../src/libraries/RafflErrors.sol";

import { Common } from "../../utils/Common.sol";
import { ERC721Mock } from "../../mocks/ERC721Mock.sol";
import { ERC20Mock } from "../../mocks/ERC20Mock.sol";

contract RafflERC721PrizesTest is Common {
    Raffl raffl;
    ERC721Mock nft1;
    ERC721Mock nft2;
    ERC721Mock nft3;
    ERC20Mock token;

    function setUp() public virtual {
        nft1 = new ERC721Mock();
        nft2 = new ERC721Mock();
        nft3 = new ERC721Mock();
        token = new ERC20Mock();
    }

    /*//////////////////////////////////////////////////////////////
                        SINGLE ERC721 PRIZE
    //////////////////////////////////////////////////////////////*/

    /// @dev Should create raffle with single ERC721 prize
    function test_CreateRaffleWithSingleNFT() public {
        nft1.mint(raffleCreator, 1);

        vm.startPrank(raffleCreator);
        nft1.approve(address(rafflFactory), 1);

        IRaffl.Prize[] memory nftPrizes = new IRaffl.Prize[](1);
        nftPrizes[0] = IRaffl.Prize(address(nft1), IRaffl.AssetType.ERC721, 1);

        raffl = Raffl(
            rafflFactory.createRaffle(
                address(0),
                ENTRY_PRICE,
                MIN_ENTRIES,
                block.timestamp + DEADLINE_FROM_NOW,
                nftPrizes,
                tokenGates,
                extraRecipient
            )
        );
        vm.stopPrank();

        // Verify NFT transferred to raffle
        assertEq(nft1.ownerOf(1), address(raffl));

        // Verify prizes stored correctly
        IRaffl.Prize[] memory storedPrizes = raffl.getPrizes();
        assertEq(storedPrizes.length, 1);
        assertEq(storedPrizes[0].asset, address(nft1));
        assertEq(uint8(storedPrizes[0].assetType), uint8(IRaffl.AssetType.ERC721));
        assertEq(storedPrizes[0].value, 1);
    }

    /// @dev Should transfer single ERC721 prize to winner
    function test_TransferSingleNFTPrizeToWinner() public {
        nft1.mint(raffleCreator, 1);

        vm.startPrank(raffleCreator);
        nft1.approve(address(rafflFactory), 1);

        IRaffl.Prize[] memory nftPrizes = new IRaffl.Prize[](1);
        nftPrizes[0] = IRaffl.Prize(address(nft1), IRaffl.AssetType.ERC721, 1);

        raffl = Raffl(
            rafflFactory.createRaffle(
                address(0),
                ENTRY_PRICE,
                MIN_ENTRIES,
                block.timestamp + DEADLINE_FROM_NOW,
                nftPrizes,
                tokenGates,
                extraRecipient
            )
        );
        vm.stopPrank();

        // Buy enough entries
        makeUserBuyEntries(raffl, userA, MIN_ENTRIES);

        // Process raffle
        vm.warp(raffl.deadline());
        uint256 requestId = performUpkeepOnActiveRaffl(raffl);
        fullfillVRFOnActiveAndEligibleRaffle(requestId, address(rafflFactory));

        // Verify winner received NFT
        address winner = raffl.winner();
        assertEq(nft1.ownerOf(1), winner);
    }

    /*//////////////////////////////////////////////////////////////
                        MULTIPLE ERC721 PRIZES
    //////////////////////////////////////////////////////////////*/

    /// @dev Should create raffle with multiple ERC721 prizes from same collection
    function test_CreateRaffleWithMultipleNFTsSameCollection() public {
        nft1.mint(raffleCreator, 1);
        nft1.mint(raffleCreator, 2);
        nft1.mint(raffleCreator, 3);

        vm.startPrank(raffleCreator);
        nft1.approve(address(rafflFactory), 1);
        nft1.approve(address(rafflFactory), 2);
        nft1.approve(address(rafflFactory), 3);

        IRaffl.Prize[] memory nftPrizes = new IRaffl.Prize[](3);
        nftPrizes[0] = IRaffl.Prize(address(nft1), IRaffl.AssetType.ERC721, 1);
        nftPrizes[1] = IRaffl.Prize(address(nft1), IRaffl.AssetType.ERC721, 2);
        nftPrizes[2] = IRaffl.Prize(address(nft1), IRaffl.AssetType.ERC721, 3);

        raffl = Raffl(
            rafflFactory.createRaffle(
                address(0),
                ENTRY_PRICE,
                MIN_ENTRIES,
                block.timestamp + DEADLINE_FROM_NOW,
                nftPrizes,
                tokenGates,
                extraRecipient
            )
        );
        vm.stopPrank();

        // Verify all NFTs transferred
        assertEq(nft1.ownerOf(1), address(raffl));
        assertEq(nft1.ownerOf(2), address(raffl));
        assertEq(nft1.ownerOf(3), address(raffl));

        IRaffl.Prize[] memory storedPrizes = raffl.getPrizes();
        assertEq(storedPrizes.length, 3);
    }

    /// @dev Should create raffle with multiple ERC721 prizes from different collections
    function test_CreateRaffleWithNFTsFromDifferentCollections() public {
        nft1.mint(raffleCreator, 10);
        nft2.mint(raffleCreator, 20);
        nft3.mint(raffleCreator, 30);

        vm.startPrank(raffleCreator);
        nft1.approve(address(rafflFactory), 10);
        nft2.approve(address(rafflFactory), 20);
        nft3.approve(address(rafflFactory), 30);

        IRaffl.Prize[] memory nftPrizes = new IRaffl.Prize[](3);
        nftPrizes[0] = IRaffl.Prize(address(nft1), IRaffl.AssetType.ERC721, 10);
        nftPrizes[1] = IRaffl.Prize(address(nft2), IRaffl.AssetType.ERC721, 20);
        nftPrizes[2] = IRaffl.Prize(address(nft3), IRaffl.AssetType.ERC721, 30);

        raffl = Raffl(
            rafflFactory.createRaffle(
                address(0),
                ENTRY_PRICE,
                MIN_ENTRIES,
                block.timestamp + DEADLINE_FROM_NOW,
                nftPrizes,
                tokenGates,
                extraRecipient
            )
        );
        vm.stopPrank();

        assertEq(nft1.ownerOf(10), address(raffl));
        assertEq(nft2.ownerOf(20), address(raffl));
        assertEq(nft3.ownerOf(30), address(raffl));
    }

    /// @dev Should transfer all NFTs to winner from different collections
    function test_TransferAllNFTsToWinnerFromDifferentCollections() public {
        nft1.mint(raffleCreator, 10);
        nft2.mint(raffleCreator, 20);
        nft3.mint(raffleCreator, 30);

        vm.startPrank(raffleCreator);
        nft1.approve(address(rafflFactory), 10);
        nft2.approve(address(rafflFactory), 20);
        nft3.approve(address(rafflFactory), 30);

        IRaffl.Prize[] memory nftPrizes = new IRaffl.Prize[](3);
        nftPrizes[0] = IRaffl.Prize(address(nft1), IRaffl.AssetType.ERC721, 10);
        nftPrizes[1] = IRaffl.Prize(address(nft2), IRaffl.AssetType.ERC721, 20);
        nftPrizes[2] = IRaffl.Prize(address(nft3), IRaffl.AssetType.ERC721, 30);

        raffl = Raffl(
            rafflFactory.createRaffle(
                address(0),
                ENTRY_PRICE,
                MIN_ENTRIES,
                block.timestamp + DEADLINE_FROM_NOW,
                nftPrizes,
                tokenGates,
                extraRecipient
            )
        );
        vm.stopPrank();

        makeUserBuyEntries(raffl, userA, MIN_ENTRIES);

        vm.warp(raffl.deadline());
        uint256 requestId = performUpkeepOnActiveRaffl(raffl);
        fullfillVRFOnActiveAndEligibleRaffle(requestId, address(rafflFactory));

        address winner = raffl.winner();
        assertEq(nft1.ownerOf(10), winner);
        assertEq(nft2.ownerOf(20), winner);
        assertEq(nft3.ownerOf(30), winner);
    }

    /*//////////////////////////////////////////////////////////////
                        MIXED ERC20 AND ERC721 PRIZES
    //////////////////////////////////////////////////////////////*/

    /// @dev Should create raffle with mixed ERC20 and ERC721 prizes
    function test_CreateRaffleWithMixedPrizes() public {
        token.mint(raffleCreator, 1000 ether);
        nft1.mint(raffleCreator, 1);
        nft2.mint(raffleCreator, 42);

        vm.startPrank(raffleCreator);
        token.approve(address(rafflFactory), 1000 ether);
        nft1.approve(address(rafflFactory), 1);
        nft2.approve(address(rafflFactory), 42);

        IRaffl.Prize[] memory mixedPrizes = new IRaffl.Prize[](3);
        mixedPrizes[0] = IRaffl.Prize(address(token), IRaffl.AssetType.ERC20, 1000 ether);
        mixedPrizes[1] = IRaffl.Prize(address(nft1), IRaffl.AssetType.ERC721, 1);
        mixedPrizes[2] = IRaffl.Prize(address(nft2), IRaffl.AssetType.ERC721, 42);

        raffl = Raffl(
            rafflFactory.createRaffle(
                address(0),
                ENTRY_PRICE,
                MIN_ENTRIES,
                block.timestamp + DEADLINE_FROM_NOW,
                mixedPrizes,
                tokenGates,
                extraRecipient
            )
        );
        vm.stopPrank();

        // Verify all prizes transferred
        assertEq(token.balanceOf(address(raffl)), 1000 ether);
        assertEq(nft1.ownerOf(1), address(raffl));
        assertEq(nft2.ownerOf(42), address(raffl));

        IRaffl.Prize[] memory storedPrizes = raffl.getPrizes();
        assertEq(storedPrizes.length, 3);
    }

    /// @dev Should transfer all mixed prizes to winner
    function test_TransferMixedPrizesToWinner() public {
        token.mint(raffleCreator, 500 ether);
        nft1.mint(raffleCreator, 99);

        vm.startPrank(raffleCreator);
        token.approve(address(rafflFactory), 500 ether);
        nft1.approve(address(rafflFactory), 99);

        IRaffl.Prize[] memory mixedPrizes = new IRaffl.Prize[](2);
        mixedPrizes[0] = IRaffl.Prize(address(token), IRaffl.AssetType.ERC20, 500 ether);
        mixedPrizes[1] = IRaffl.Prize(address(nft1), IRaffl.AssetType.ERC721, 99);

        raffl = Raffl(
            rafflFactory.createRaffle(
                address(0),
                ENTRY_PRICE,
                MIN_ENTRIES,
                block.timestamp + DEADLINE_FROM_NOW,
                mixedPrizes,
                tokenGates,
                extraRecipient
            )
        );
        vm.stopPrank();

        makeUserBuyEntries(raffl, userA, MIN_ENTRIES);

        vm.warp(raffl.deadline());
        uint256 requestId = performUpkeepOnActiveRaffl(raffl);
        fullfillVRFOnActiveAndEligibleRaffle(requestId, address(rafflFactory));

        address winner = raffl.winner();
        assertEq(token.balanceOf(winner), 500 ether);
        assertEq(nft1.ownerOf(99), winner);
    }

    /*//////////////////////////////////////////////////////////////
                        ERC721 ONLY PRIZES (NO ERC20)
    //////////////////////////////////////////////////////////////*/

    /// @dev Should handle raffle with only NFT prizes and native entry
    function test_NFTOnlyPrizesWithNativeEntry() public {
        nft1.mint(raffleCreator, 1);
        nft1.mint(raffleCreator, 2);

        vm.startPrank(raffleCreator);
        nft1.approve(address(rafflFactory), 1);
        nft1.approve(address(rafflFactory), 2);

        IRaffl.Prize[] memory nftOnlyPrizes = new IRaffl.Prize[](2);
        nftOnlyPrizes[0] = IRaffl.Prize(address(nft1), IRaffl.AssetType.ERC721, 1);
        nftOnlyPrizes[1] = IRaffl.Prize(address(nft1), IRaffl.AssetType.ERC721, 2);

        raffl = Raffl(
            rafflFactory.createRaffle(
                address(0), // Native entry
                ENTRY_PRICE,
                MIN_ENTRIES,
                block.timestamp + DEADLINE_FROM_NOW,
                nftOnlyPrizes,
                tokenGates,
                extraRecipient
            )
        );
        vm.stopPrank();

        makeUserBuyEntries(raffl, userA, MIN_ENTRIES);

        vm.warp(raffl.deadline());
        uint256 requestId = performUpkeepOnActiveRaffl(raffl);
        fullfillVRFOnActiveAndEligibleRaffle(requestId, address(rafflFactory));

        address winner = raffl.winner();
        assertEq(nft1.ownerOf(1), winner);
        assertEq(nft1.ownerOf(2), winner);
    }

    /*//////////////////////////////////////////////////////////////
                        REFUND ERC721 PRIZES ON FAILED DRAW
    //////////////////////////////////////////////////////////////*/

    /// @dev Should refund ERC721 prizes to creator on failed draw
    function test_RefundNFTPrizesOnFailedDraw() public {
        nft1.mint(raffleCreator, 1);
        nft2.mint(raffleCreator, 5);

        vm.startPrank(raffleCreator);
        nft1.approve(address(rafflFactory), 1);
        nft2.approve(address(rafflFactory), 5);

        IRaffl.Prize[] memory nftPrizes = new IRaffl.Prize[](2);
        nftPrizes[0] = IRaffl.Prize(address(nft1), IRaffl.AssetType.ERC721, 1);
        nftPrizes[1] = IRaffl.Prize(address(nft2), IRaffl.AssetType.ERC721, 5);

        raffl = Raffl(
            rafflFactory.createRaffle(
                address(0),
                ENTRY_PRICE,
                MIN_ENTRIES,
                block.timestamp + DEADLINE_FROM_NOW,
                nftPrizes,
                tokenGates,
                extraRecipient
            )
        );
        vm.stopPrank();

        // Don't meet minimum entries
        makeUserBuyEntries(raffl, userA, 1);

        // Process failed draw
        vm.warp(raffl.deadline());
        performUpkeepOnActiveRaffl(raffl);

        assertEq(uint8(raffl.gameStatus()), uint8(IRaffl.GameStatus.FailedDraw));

        // Creator refunds prizes
        vm.prank(raffleCreator);
        raffl.refundPrizes();

        // Verify NFTs returned to creator
        assertEq(nft1.ownerOf(1), raffleCreator);
        assertEq(nft2.ownerOf(5), raffleCreator);
    }

    /// @dev Should refund mixed prizes to creator on failed draw
    function test_RefundMixedPrizesOnFailedDraw() public {
        token.mint(raffleCreator, 100 ether);
        nft1.mint(raffleCreator, 7);

        vm.startPrank(raffleCreator);
        token.approve(address(rafflFactory), 100 ether);
        nft1.approve(address(rafflFactory), 7);

        IRaffl.Prize[] memory mixedPrizes = new IRaffl.Prize[](2);
        mixedPrizes[0] = IRaffl.Prize(address(token), IRaffl.AssetType.ERC20, 100 ether);
        mixedPrizes[1] = IRaffl.Prize(address(nft1), IRaffl.AssetType.ERC721, 7);

        raffl = Raffl(
            rafflFactory.createRaffle(
                address(0),
                ENTRY_PRICE,
                MIN_ENTRIES,
                block.timestamp + DEADLINE_FROM_NOW,
                mixedPrizes,
                tokenGates,
                extraRecipient
            )
        );
        vm.stopPrank();

        // Don't meet minimum entries
        makeUserBuyEntries(raffl, userA, 1);

        // Process failed draw
        vm.warp(raffl.deadline());
        performUpkeepOnActiveRaffl(raffl);

        // Creator refunds prizes
        vm.prank(raffleCreator);
        raffl.refundPrizes();

        // Verify all prizes returned
        assertEq(token.balanceOf(raffleCreator), 100 ether);
        assertEq(nft1.ownerOf(7), raffleCreator);
    }

    /*//////////////////////////////////////////////////////////////
                        LARGE NUMBER OF ERC721 PRIZES
    //////////////////////////////////////////////////////////////*/

    /// @dev Should handle raffle with many ERC721 prizes
    function test_ManyNFTPrizes() public {
        uint256 numNFTs = 20;
        IRaffl.Prize[] memory manyNFTs = new IRaffl.Prize[](numNFTs);

        vm.startPrank(raffleCreator);
        for (uint256 i = 0; i < numNFTs; i++) {
            nft1.mint(raffleCreator, i);
            nft1.approve(address(rafflFactory), i);
            manyNFTs[i] = IRaffl.Prize(address(nft1), IRaffl.AssetType.ERC721, i);
        }

        raffl = Raffl(
            rafflFactory.createRaffle(
                address(0),
                ENTRY_PRICE,
                MIN_ENTRIES,
                block.timestamp + DEADLINE_FROM_NOW,
                manyNFTs,
                tokenGates,
                extraRecipient
            )
        );
        vm.stopPrank();

        // Verify all NFTs transferred
        for (uint256 i = 0; i < numNFTs; i++) {
            assertEq(nft1.ownerOf(i), address(raffl));
        }

        // Complete raffle
        makeUserBuyEntries(raffl, userA, MIN_ENTRIES);
        vm.warp(raffl.deadline());
        uint256 requestId = performUpkeepOnActiveRaffl(raffl);
        fullfillVRFOnActiveAndEligibleRaffle(requestId, address(rafflFactory));

        // Verify winner received all NFTs
        address winner = raffl.winner();
        for (uint256 i = 0; i < numNFTs; i++) {
            assertEq(nft1.ownerOf(i), winner);
        }
    }

    /*//////////////////////////////////////////////////////////////
                        ERC721 TOKEN ID EDGE CASES
    //////////////////////////////////////////////////////////////*/

    /// @dev Should handle ERC721 with tokenId 0
    function test_NFTWithTokenIdZero() public {
        nft1.mint(raffleCreator, 0);

        vm.startPrank(raffleCreator);
        nft1.approve(address(rafflFactory), 0);

        IRaffl.Prize[] memory nftPrizes = new IRaffl.Prize[](1);
        nftPrizes[0] = IRaffl.Prize(address(nft1), IRaffl.AssetType.ERC721, 0);

        raffl = Raffl(
            rafflFactory.createRaffle(
                address(0),
                ENTRY_PRICE,
                MIN_ENTRIES,
                block.timestamp + DEADLINE_FROM_NOW,
                nftPrizes,
                tokenGates,
                extraRecipient
            )
        );
        vm.stopPrank();

        assertEq(nft1.ownerOf(0), address(raffl));

        makeUserBuyEntries(raffl, userA, MIN_ENTRIES);
        vm.warp(raffl.deadline());
        uint256 requestId = performUpkeepOnActiveRaffl(raffl);
        fullfillVRFOnActiveAndEligibleRaffle(requestId, address(rafflFactory));

        assertEq(nft1.ownerOf(0), raffl.winner());
    }

    /// @dev Should handle ERC721 with large tokenId
    function test_NFTWithLargeTokenId() public {
        uint256 largeTokenId = type(uint256).max - 1;
        nft1.mint(raffleCreator, largeTokenId);

        vm.startPrank(raffleCreator);
        nft1.approve(address(rafflFactory), largeTokenId);

        IRaffl.Prize[] memory nftPrizes = new IRaffl.Prize[](1);
        nftPrizes[0] = IRaffl.Prize(address(nft1), IRaffl.AssetType.ERC721, largeTokenId);

        raffl = Raffl(
            rafflFactory.createRaffle(
                address(0),
                ENTRY_PRICE,
                MIN_ENTRIES,
                block.timestamp + DEADLINE_FROM_NOW,
                nftPrizes,
                tokenGates,
                extraRecipient
            )
        );
        vm.stopPrank();

        assertEq(nft1.ownerOf(largeTokenId), address(raffl));

        makeUserBuyEntries(raffl, userA, MIN_ENTRIES);
        vm.warp(raffl.deadline());
        uint256 requestId = performUpkeepOnActiveRaffl(raffl);
        fullfillVRFOnActiveAndEligibleRaffle(requestId, address(rafflFactory));

        assertEq(nft1.ownerOf(largeTokenId), raffl.winner());
    }

    /*//////////////////////////////////////////////////////////////
                        getPrizes() VIEW FUNCTION TESTS
    //////////////////////////////////////////////////////////////*/

    /// @dev Should return correct prizes array after creation
    function test_GetPrizesReturnsCorrectData() public {
        token.mint(raffleCreator, 250 ether);
        nft1.mint(raffleCreator, 5);
        nft2.mint(raffleCreator, 10);

        vm.startPrank(raffleCreator);
        token.approve(address(rafflFactory), 250 ether);
        nft1.approve(address(rafflFactory), 5);
        nft2.approve(address(rafflFactory), 10);

        IRaffl.Prize[] memory inputPrizes = new IRaffl.Prize[](3);
        inputPrizes[0] = IRaffl.Prize(address(token), IRaffl.AssetType.ERC20, 250 ether);
        inputPrizes[1] = IRaffl.Prize(address(nft1), IRaffl.AssetType.ERC721, 5);
        inputPrizes[2] = IRaffl.Prize(address(nft2), IRaffl.AssetType.ERC721, 10);

        raffl = Raffl(
            rafflFactory.createRaffle(
                address(0),
                ENTRY_PRICE,
                MIN_ENTRIES,
                block.timestamp + DEADLINE_FROM_NOW,
                inputPrizes,
                tokenGates,
                extraRecipient
            )
        );
        vm.stopPrank();

        IRaffl.Prize[] memory retrievedPrizes = raffl.getPrizes();

        assertEq(retrievedPrizes.length, 3);

        assertEq(retrievedPrizes[0].asset, address(token));
        assertEq(uint8(retrievedPrizes[0].assetType), uint8(IRaffl.AssetType.ERC20));
        assertEq(retrievedPrizes[0].value, 250 ether);

        assertEq(retrievedPrizes[1].asset, address(nft1));
        assertEq(uint8(retrievedPrizes[1].assetType), uint8(IRaffl.AssetType.ERC721));
        assertEq(retrievedPrizes[1].value, 5);

        assertEq(retrievedPrizes[2].asset, address(nft2));
        assertEq(uint8(retrievedPrizes[2].assetType), uint8(IRaffl.AssetType.ERC721));
        assertEq(retrievedPrizes[2].value, 10);
    }
}
