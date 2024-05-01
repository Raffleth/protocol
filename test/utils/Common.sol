// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.24;

import { Test } from "forge-std/src/Test.sol";

import { VRFCoordinatorV2Mock } from "@chainlink/contracts/src/v0.8/vrf/mocks/VRFCoordinatorV2Mock.sol";

import { Raffl } from "../../src/Raffl.sol";
import { IRaffl } from "../../src/interfaces/IRaffl.sol";
import { RafflFactory } from "../../src/RafflFactory.sol";

import { ERC20Mock } from "../mocks/ERC20Mock.sol";
import { ERC721Mock } from "../mocks/ERC721Mock.sol";

contract Common is Test {
    // Addresses
    address admin = address(10);
    address feeCollector = address(11);
    address raffleCreator = address(12);
    address userA = address(13);
    address userB = address(14);
    address userC = address(15);
    address userD = address(16);
    address externalUser = address(17);
    address attacker = address(18);

    // Contracts
    VRFCoordinatorV2Mock vrfCoordinatorV2Mock;
    Raffl implementation;
    RafflFactory rafflFactory;
    ERC721Mock testERC721;
    ERC20Mock testERC20;

    // Test states
    IRaffl.ExtraRecipient extraRecipient;
    IRaffl.TokenGate[] tokenGates;
    IRaffl.Prize[] prizes;
    uint256 ERC20_AMOUNT = 50 ether;
    uint256 ERC721_TOKEN_ID = 0;
    uint256 ENTRY_PRICE = 2 ether;
    uint256 MIN_ENTRIES = 10;
    uint256 DEADLINE_FROM_NOW = 86_400;
    bytes32 CHECK_DATA;

    // Network configs
    uint64 feePercentage = 0.05 ether;
    uint256 feePenality = 0;
    bytes32 chainlinkKeyHash = 0xd89b2bf150e3b9e13446986e571fb9cab24b13cea0a43ea20a6049a85cc807cc;
    uint64 chainlinkSubscriptionId = 1;

    constructor() {
        // Instantiate Chainlink VRF Coordinator V2 Mock
        vrfCoordinatorV2Mock = new VRFCoordinatorV2Mock(0.1 ether, 1_000_000_000);

        // Create Chainlink subscription
        chainlinkSubscriptionId = vrfCoordinatorV2Mock.createSubscription();

        // Fund Chainlink subscription
        vrfCoordinatorV2Mock.fundSubscription(chainlinkSubscriptionId, 100_000_000_000_000_000_000);

        // Instantiate the Raffl implementation
        implementation = new Raffl();

        // Instantiate the factory
        rafflFactory = new RafflFactory(
            address(implementation),
            feeCollector,
            feePercentage,
            feePenality,
            address(vrfCoordinatorV2Mock),
            chainlinkKeyHash,
            chainlinkSubscriptionId
        );

        // Add RafflFactory as Cosnumer
        vrfCoordinatorV2Mock.addConsumer(chainlinkSubscriptionId, address(rafflFactory));

        // Transfer Ownership to admin
        rafflFactory.transferOwnership(admin);
        vm.prank(admin);
        rafflFactory.acceptOwnership();
    }

    function deployErc20AndFund(address owner) public {
        testERC20 = new ERC20Mock();
        testERC20.mint(owner, ERC20_AMOUNT);
    }

    function deployErc721AndFund(address owner) public {
        testERC721 = new ERC721Mock();
        testERC721.mint(owner, ERC721_TOKEN_ID);
    }
}
