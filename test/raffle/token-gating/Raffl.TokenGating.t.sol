// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.33;

import { Raffl } from "../../../src/Raffl.sol";
import { IRaffl } from "../../../src/interfaces/IRaffl.sol";
import { Errors } from "../../../src/libraries/RafflErrors.sol";

import { Common } from "../../utils/Common.sol";
import { ERC20Mock } from "../../mocks/ERC20Mock.sol";
import { ERC721Mock } from "../../mocks/ERC721Mock.sol";

contract RafflTokenGatingTest is Common {
    Raffl raffl;
    ERC20Mock gateToken;
    ERC721Mock gateNFT;

    uint256 constant GATE_AMOUNT = 100 ether;
    uint256 constant NFT_TOKEN_ID = 42;

    function setUp() public virtual {
        fundAndSetPrizes(raffleCreator);

        // Deploy gate tokens
        gateToken = new ERC20Mock();
        gateNFT = new ERC721Mock();
    }

    /// @dev Helper to create raffle with token gates
    function _createRaffleWithTokenGates(IRaffl.TokenGate[] memory gates) internal returns (Raffl) {
        vm.prank(raffleCreator);
        return Raffl(
            rafflFactory.createRaffle(
                address(0),
                ENTRY_PRICE,
                MIN_ENTRIES,
                block.timestamp + DEADLINE_FROM_NOW,
                prizes,
                gates,
                extraRecipient
            )
        );
    }

    /*//////////////////////////////////////////////////////////////
                        SINGLE ERC20 TOKEN GATE
    //////////////////////////////////////////////////////////////*/

    /// @dev Should allow entry when user meets ERC20 token gate requirement
    function test_AllowsEntryWhenERC20GateMet() public {
        // Setup token gate
        IRaffl.TokenGate[] memory gates = new IRaffl.TokenGate[](1);
        gates[0] = IRaffl.TokenGate({ token: address(gateToken), amount: GATE_AMOUNT });

        raffl = _createRaffleWithTokenGates(gates);

        // Fund user with gate tokens
        gateToken.mint(userA, GATE_AMOUNT);

        // User should be able to buy entries
        makeUserBuyEntries(raffl, userA, 5);

        assertEq(raffl.balanceOf(userA), 5);
    }

    /// @dev Should revert entry when user doesn't meet ERC20 token gate requirement
    function test_RevertIf_ERC20GateNotMet() public {
        IRaffl.TokenGate[] memory gates = new IRaffl.TokenGate[](1);
        gates[0] = IRaffl.TokenGate({ token: address(gateToken), amount: GATE_AMOUNT });

        raffl = _createRaffleWithTokenGates(gates);

        // User has no gate tokens
        uint256 entryPrice = raffl.entryPrice();
        vm.deal(userA, entryPrice * 5);

        vm.expectRevert(Errors.TokenGateRestriction.selector);
        vm.prank(userA);
        raffl.buyEntries{ value: entryPrice * 5 }(5);
    }

    /// @dev Should revert entry when user has insufficient ERC20 token gate balance
    function test_RevertIf_ERC20GateInsufficientBalance() public {
        IRaffl.TokenGate[] memory gates = new IRaffl.TokenGate[](1);
        gates[0] = IRaffl.TokenGate({ token: address(gateToken), amount: GATE_AMOUNT });

        raffl = _createRaffleWithTokenGates(gates);

        // User has less than required
        gateToken.mint(userA, GATE_AMOUNT - 1);

        uint256 entryPrice = raffl.entryPrice();
        vm.deal(userA, entryPrice * 5);

        vm.expectRevert(Errors.TokenGateRestriction.selector);
        vm.prank(userA);
        raffl.buyEntries{ value: entryPrice * 5 }(5);
    }

    /// @dev Should allow entry when user has exactly the required ERC20 balance
    function test_AllowsEntryWhenERC20GateExactBalance() public {
        IRaffl.TokenGate[] memory gates = new IRaffl.TokenGate[](1);
        gates[0] = IRaffl.TokenGate({ token: address(gateToken), amount: GATE_AMOUNT });

        raffl = _createRaffleWithTokenGates(gates);

        // User has exactly the required amount
        gateToken.mint(userA, GATE_AMOUNT);

        makeUserBuyEntries(raffl, userA, 3);
        assertEq(raffl.balanceOf(userA), 3);
    }

    /*//////////////////////////////////////////////////////////////
                        SINGLE ERC721 TOKEN GATE
    //////////////////////////////////////////////////////////////*/

    /// @dev Should allow entry when user owns required NFT
    function test_AllowsEntryWhenERC721GateMet() public {
        IRaffl.TokenGate[] memory gates = new IRaffl.TokenGate[](1);
        // For ERC721, amount = 1 means user must own at least 1 NFT
        gates[0] = IRaffl.TokenGate({ token: address(gateNFT), amount: 1 });

        raffl = _createRaffleWithTokenGates(gates);

        // Mint NFT to user
        gateNFT.mint(userA, NFT_TOKEN_ID);

        makeUserBuyEntries(raffl, userA, 5);
        assertEq(raffl.balanceOf(userA), 5);
    }

    /// @dev Should revert entry when user doesn't own required NFT
    function test_RevertIf_ERC721GateNotMet() public {
        IRaffl.TokenGate[] memory gates = new IRaffl.TokenGate[](1);
        gates[0] = IRaffl.TokenGate({ token: address(gateNFT), amount: 1 });

        raffl = _createRaffleWithTokenGates(gates);

        // User has no NFTs
        uint256 entryPrice = raffl.entryPrice();
        vm.deal(userA, entryPrice * 5);

        vm.expectRevert(Errors.TokenGateRestriction.selector);
        vm.prank(userA);
        raffl.buyEntries{ value: entryPrice * 5 }(5);
    }

    /// @dev Should allow entry when user owns multiple NFTs and gate requires more than 1
    function test_AllowsEntryWhenMultipleNFTsRequired() public {
        IRaffl.TokenGate[] memory gates = new IRaffl.TokenGate[](1);
        gates[0] = IRaffl.TokenGate({ token: address(gateNFT), amount: 3 });

        raffl = _createRaffleWithTokenGates(gates);

        // Mint 3 NFTs to user
        gateNFT.mint(userA, 1);
        gateNFT.mint(userA, 2);
        gateNFT.mint(userA, 3);

        makeUserBuyEntries(raffl, userA, 5);
        assertEq(raffl.balanceOf(userA), 5);
    }

    /// @dev Should revert when user has fewer NFTs than required
    function test_RevertIf_InsufficientNFTCount() public {
        IRaffl.TokenGate[] memory gates = new IRaffl.TokenGate[](1);
        gates[0] = IRaffl.TokenGate({ token: address(gateNFT), amount: 3 });

        raffl = _createRaffleWithTokenGates(gates);

        // Mint only 2 NFTs
        gateNFT.mint(userA, 1);
        gateNFT.mint(userA, 2);

        uint256 entryPrice = raffl.entryPrice();
        vm.deal(userA, entryPrice * 5);

        vm.expectRevert(Errors.TokenGateRestriction.selector);
        vm.prank(userA);
        raffl.buyEntries{ value: entryPrice * 5 }(5);
    }

    /*//////////////////////////////////////////////////////////////
                        MULTIPLE TOKEN GATES
    //////////////////////////////////////////////////////////////*/

    /// @dev Should allow entry when user meets all multiple token gates
    function test_AllowsEntryWhenAllGatesMet() public {
        ERC20Mock gateToken2 = new ERC20Mock();

        IRaffl.TokenGate[] memory gates = new IRaffl.TokenGate[](3);
        gates[0] = IRaffl.TokenGate({ token: address(gateToken), amount: GATE_AMOUNT });
        gates[1] = IRaffl.TokenGate({ token: address(gateNFT), amount: 1 });
        gates[2] = IRaffl.TokenGate({ token: address(gateToken2), amount: 50 ether });

        raffl = _createRaffleWithTokenGates(gates);

        // Fund user with all required tokens
        gateToken.mint(userA, GATE_AMOUNT);
        gateNFT.mint(userA, NFT_TOKEN_ID);
        gateToken2.mint(userA, 50 ether);

        makeUserBuyEntries(raffl, userA, 5);
        assertEq(raffl.balanceOf(userA), 5);
    }

    /// @dev Should revert when user fails any single token gate among multiple
    function test_RevertIf_AnyGateNotMet() public {
        ERC20Mock gateToken2 = new ERC20Mock();

        IRaffl.TokenGate[] memory gates = new IRaffl.TokenGate[](3);
        gates[0] = IRaffl.TokenGate({ token: address(gateToken), amount: GATE_AMOUNT });
        gates[1] = IRaffl.TokenGate({ token: address(gateNFT), amount: 1 });
        gates[2] = IRaffl.TokenGate({ token: address(gateToken2), amount: 50 ether });

        raffl = _createRaffleWithTokenGates(gates);

        // User has first two requirements but not the third
        gateToken.mint(userA, GATE_AMOUNT);
        gateNFT.mint(userA, NFT_TOKEN_ID);
        // Missing: gateToken2

        uint256 entryPrice = raffl.entryPrice();
        vm.deal(userA, entryPrice * 5);

        vm.expectRevert(Errors.TokenGateRestriction.selector);
        vm.prank(userA);
        raffl.buyEntries{ value: entryPrice * 5 }(5);
    }

    /// @dev Should revert when user fails the first gate among multiple
    function test_RevertIf_FirstGateNotMet() public {
        IRaffl.TokenGate[] memory gates = new IRaffl.TokenGate[](2);
        gates[0] = IRaffl.TokenGate({ token: address(gateToken), amount: GATE_AMOUNT });
        gates[1] = IRaffl.TokenGate({ token: address(gateNFT), amount: 1 });

        raffl = _createRaffleWithTokenGates(gates);

        // User only has NFT, not ERC20
        gateNFT.mint(userA, NFT_TOKEN_ID);

        uint256 entryPrice = raffl.entryPrice();
        vm.deal(userA, entryPrice * 5);

        vm.expectRevert(Errors.TokenGateRestriction.selector);
        vm.prank(userA);
        raffl.buyEntries{ value: entryPrice * 5 }(5);
    }

    /// @dev Should revert when user fails the last gate among multiple
    function test_RevertIf_LastGateNotMet() public {
        IRaffl.TokenGate[] memory gates = new IRaffl.TokenGate[](2);
        gates[0] = IRaffl.TokenGate({ token: address(gateToken), amount: GATE_AMOUNT });
        gates[1] = IRaffl.TokenGate({ token: address(gateNFT), amount: 1 });

        raffl = _createRaffleWithTokenGates(gates);

        // User only has ERC20, not NFT
        gateToken.mint(userA, GATE_AMOUNT);

        uint256 entryPrice = raffl.entryPrice();
        vm.deal(userA, entryPrice * 5);

        vm.expectRevert(Errors.TokenGateRestriction.selector);
        vm.prank(userA);
        raffl.buyEntries{ value: entryPrice * 5 }(5);
    }

    /*//////////////////////////////////////////////////////////////
                        TOKEN GATE WITH FREE ENTRIES
    //////////////////////////////////////////////////////////////*/

    /// @dev Should allow free entry when token gate is met
    function test_AllowsFreeEntryWhenGateMet() public {
        IRaffl.TokenGate[] memory gates = new IRaffl.TokenGate[](1);
        gates[0] = IRaffl.TokenGate({ token: address(gateToken), amount: GATE_AMOUNT });

        // Create free raffle with token gate
        vm.prank(raffleCreator);
        raffl = Raffl(
            rafflFactory.createRaffle(
                address(0),
                0, // Free entry
                MIN_ENTRIES,
                block.timestamp + DEADLINE_FROM_NOW,
                prizes,
                gates,
                extraRecipient
            )
        );

        // Fund user with gate tokens
        gateToken.mint(userA, GATE_AMOUNT);

        vm.prank(userA);
        raffl.buyEntries(1);

        assertEq(raffl.balanceOf(userA), 1);
    }

    /// @dev Should revert free entry when token gate not met
    function test_RevertIf_FreeEntryGateNotMet() public {
        IRaffl.TokenGate[] memory gates = new IRaffl.TokenGate[](1);
        gates[0] = IRaffl.TokenGate({ token: address(gateToken), amount: GATE_AMOUNT });

        // Create free raffle with token gate
        vm.prank(raffleCreator);
        raffl = Raffl(
            rafflFactory.createRaffle(
                address(0),
                0, // Free entry
                MIN_ENTRIES,
                block.timestamp + DEADLINE_FROM_NOW,
                prizes,
                gates,
                extraRecipient
            )
        );

        // User has no gate tokens
        vm.expectRevert(Errors.TokenGateRestriction.selector);
        vm.prank(userA);
        raffl.buyEntries(1);
    }

    /*//////////////////////////////////////////////////////////////
                    TOKEN GATE PERSISTENCE ACROSS ENTRIES
    //////////////////////////////////////////////////////////////*/

    /// @dev Should check token gate on each entry purchase
    function test_TokenGateCheckedOnEachPurchase() public {
        IRaffl.TokenGate[] memory gates = new IRaffl.TokenGate[](1);
        gates[0] = IRaffl.TokenGate({ token: address(gateToken), amount: GATE_AMOUNT });

        raffl = _createRaffleWithTokenGates(gates);

        // Fund user with gate tokens
        gateToken.mint(userA, GATE_AMOUNT);

        // First purchase succeeds
        makeUserBuyEntries(raffl, userA, 3);
        assertEq(raffl.balanceOf(userA), 3);

        // User transfers away their gate tokens
        vm.prank(userA);
        gateToken.transfer(userB, GATE_AMOUNT);

        // Second purchase should fail
        uint256 entryPrice = raffl.entryPrice();
        vm.deal(userA, entryPrice * 2);

        vm.expectRevert(Errors.TokenGateRestriction.selector);
        vm.prank(userA);
        raffl.buyEntries{ value: entryPrice * 2 }(2);
    }

    /// @dev Should allow multiple users with different gate token holdings
    function test_MultipleUsersWithGates() public {
        IRaffl.TokenGate[] memory gates = new IRaffl.TokenGate[](1);
        gates[0] = IRaffl.TokenGate({ token: address(gateToken), amount: GATE_AMOUNT });

        raffl = _createRaffleWithTokenGates(gates);

        // Fund multiple users
        gateToken.mint(userA, GATE_AMOUNT);
        gateToken.mint(userB, GATE_AMOUNT * 2);
        // userC has no tokens

        // userA and userB can participate
        makeUserBuyEntries(raffl, userA, 3);
        makeUserBuyEntries(raffl, userB, 5);

        assertEq(raffl.balanceOf(userA), 3);
        assertEq(raffl.balanceOf(userB), 5);

        // userC cannot
        uint256 entryPrice = raffl.entryPrice();
        vm.deal(userC, entryPrice * 2);

        vm.expectRevert(Errors.TokenGateRestriction.selector);
        vm.prank(userC);
        raffl.buyEntries{ value: entryPrice * 2 }(2);
    }

    /*//////////////////////////////////////////////////////////////
                        EDGE CASES
    //////////////////////////////////////////////////////////////*/

    /// @dev Should work with zero amount token gate (no restriction)
    function test_ZeroAmountGateAllowsAll() public {
        IRaffl.TokenGate[] memory gates = new IRaffl.TokenGate[](1);
        gates[0] = IRaffl.TokenGate({ token: address(gateToken), amount: 0 });

        raffl = _createRaffleWithTokenGates(gates);

        // User with no tokens can still participate (0 >= 0)
        makeUserBuyEntries(raffl, userA, 5);
        assertEq(raffl.balanceOf(userA), 5);
    }

    /// @dev Should work with very large token gate amount
    function test_LargeTokenGateAmount() public {
        uint256 largeAmount = type(uint256).max / 2;

        IRaffl.TokenGate[] memory gates = new IRaffl.TokenGate[](1);
        gates[0] = IRaffl.TokenGate({ token: address(gateToken), amount: largeAmount });

        raffl = _createRaffleWithTokenGates(gates);

        // User has enough
        gateToken.mint(userA, largeAmount);

        makeUserBuyEntries(raffl, userA, 5);
        assertEq(raffl.balanceOf(userA), 5);
    }

    /// @dev Should handle raffle with no token gates (empty array)
    function test_NoTokenGatesAllowsAll() public {
        IRaffl.TokenGate[] memory gates = new IRaffl.TokenGate[](0);

        raffl = _createRaffleWithTokenGates(gates);

        // Any user can participate
        makeUserBuyEntries(raffl, userA, 5);
        makeUserBuyEntries(raffl, userB, 3);

        assertEq(raffl.balanceOf(userA), 5);
        assertEq(raffl.balanceOf(userB), 3);
    }

    /// @dev Should work with same token in multiple gates
    function test_SameTokenMultipleGates() public {
        IRaffl.TokenGate[] memory gates = new IRaffl.TokenGate[](2);
        gates[0] = IRaffl.TokenGate({ token: address(gateToken), amount: 50 ether });
        gates[1] = IRaffl.TokenGate({ token: address(gateToken), amount: 100 ether });

        raffl = _createRaffleWithTokenGates(gates);

        // User needs to satisfy the highest requirement (100 ether)
        gateToken.mint(userA, 100 ether);

        makeUserBuyEntries(raffl, userA, 5);
        assertEq(raffl.balanceOf(userA), 5);
    }

    /// @dev Should revert with same token multiple gates when not meeting highest
    function test_RevertIf_SameTokenMultipleGatesHighestNotMet() public {
        IRaffl.TokenGate[] memory gates = new IRaffl.TokenGate[](2);
        gates[0] = IRaffl.TokenGate({ token: address(gateToken), amount: 50 ether });
        gates[1] = IRaffl.TokenGate({ token: address(gateToken), amount: 100 ether });

        raffl = _createRaffleWithTokenGates(gates);

        // User only has 75 ether (meets first gate but not second)
        gateToken.mint(userA, 75 ether);

        uint256 entryPrice = raffl.entryPrice();
        vm.deal(userA, entryPrice * 5);

        vm.expectRevert(Errors.TokenGateRestriction.selector);
        vm.prank(userA);
        raffl.buyEntries{ value: entryPrice * 5 }(5);
    }
}
