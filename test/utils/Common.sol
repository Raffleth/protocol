// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.24;

import { Test } from "forge-std/src/Test.sol";


import { Raffl } from "../../src/Raffl.sol";
import { IRaffl } from "../../src/interfaces/IRaffl.sol";
import { RafflFactory } from "../../src/RafflFactory.sol";

import { ERC20Mock } from "../mocks/ERC20Mock.sol";
import { ERC721Mock } from "../mocks/ERC721Mock.sol";
import { VRFCoordinatorV2PlusMock } from "../mocks/VRFCoordinatorV2PlusMock.sol";

abstract contract Common is Test {
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
    VRFCoordinatorV2PlusMock vrfCoordinator;
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
    bytes CHECK_DATA = abi.encode(0, 500);

    // Network configs
    uint64 feePercentage = 0.05 ether;
    uint256 feePenality = 0;
    bytes32 chainlinkKeyHash = 0x787d74caea10b2b357790d5b5247c2f63d1d91572a9846f780606e4d953677ae;
    uint256 chainlinkSubscriptionId = 420;

    constructor() {
        // Instantiate Chainlink VRF Coordinator V2 Mock
        vrfCoordinator = new VRFCoordinatorV2PlusMock(0.01 ether, 1_000_000_000);

        // Create Chainlink subscription
        chainlinkSubscriptionId = vrfCoordinator.createSubscription();

        // Fund Chainlink subscription
        vrfCoordinator.fundSubscription(chainlinkSubscriptionId, 1000 ether);

        // Instantiate the Raffl implementation
        implementation = new Raffl();

        // Instantiate the factory
        rafflFactory = new RafflFactory(
            address(implementation),
            feeCollector,
            feePercentage,
            feePenality,
            address(vrfCoordinator),
            chainlinkKeyHash,
            chainlinkSubscriptionId
        );

        // Add RafflFactory as Cosnumer
        vrfCoordinator.addConsumer(rafflFactory.subscriptionId(), address(rafflFactory));
        vrfCoordinator.consumerIsAdded(rafflFactory.subscriptionId(), address(rafflFactory));

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

    function fundAndSetPrizes(address owner) public {
        deployErc20AndFund(owner);
        deployErc721AndFund(owner);

        // Approving prize spend
        vm.startPrank(owner);
        testERC20.approve(address(rafflFactory), ERC20_AMOUNT);
        testERC721.approve(address(rafflFactory), ERC721_TOKEN_ID);
        vm.stopPrank();

        // Set prizes
        prizes.push(IRaffl.Prize(address(testERC20), IRaffl.AssetType.ERC20, ERC20_AMOUNT));
        prizes.push(IRaffl.Prize(address(testERC721), IRaffl.AssetType.ERC721, ERC721_TOKEN_ID));
    }

    function createNewRaffle(address creator) public returns (Raffl raffle) {
        vm.prank(creator);
        raffle = Raffl(
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
    }

    function makeUserBuyEntries(Raffl raffl, address user, uint256 amount) public {
        uint256 entryPrice = raffl.entryPrice();
        uint256 value = entryPrice * amount;
        vm.deal(user, value);
        vm.prank(user);
        raffl.buyEntries{ value: value }(amount);
    }

    function findActiveRaffle(Raffl raffl) public view returns (address activeRaffle, uint256 activeRaffleIdx) {
        RafflFactory.ActiveRaffle[] memory activeRaffles = rafflFactory.activeRaffles();

        for (uint256 i = 0; i < activeRaffles.length; i++) {
            if (activeRaffles[i].raffle == address(raffl)) {
                activeRaffle = address(raffl);
                activeRaffleIdx = i;
            }
        }
    }
}
