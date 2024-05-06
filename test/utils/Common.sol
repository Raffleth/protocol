// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.25;

import { Test, Vm } from "forge-std/src/Test.sol";

import { Raffl } from "../../src/Raffl.sol";
import { IRaffl } from "../../src/interfaces/IRaffl.sol";
import { RafflFactory } from "../../src/RafflFactory.sol";

import { ERC20Mock } from "../mocks/ERC20Mock.sol";
import { ERC721Mock } from "../mocks/ERC721Mock.sol";
import { VRFCoordinatorV2PlusMock } from "../mocks/VRFCoordinatorV2PlusMock.sol";

abstract contract Common is Test {
    // Addresses
    address internal admin = address(10);
    address internal feeCollector = address(11);
    address internal raffleCreator = address(12);
    address internal userA = address(13);
    address internal userB = address(14);
    address internal userC = address(15);
    address internal userD = address(16);
    address internal externalUser = address(17);
    address internal attacker = address(18);
    address internal userExtraRecipient = address(19);

    // Contracts
    VRFCoordinatorV2PlusMock internal vrfCoordinator;
    Raffl internal implementation;
    RafflFactory internal rafflFactory;
    ERC721Mock internal testERC721;
    ERC20Mock internal testERC20;

    // Test states
    IRaffl.ExtraRecipient internal extraRecipient;
    IRaffl.TokenGate[] internal tokenGates;
    IRaffl.Prize[] internal prizes;
    uint256 internal ERC20_AMOUNT = 50 ether;
    uint256 internal ERC721_TOKEN_ID = 0;
    uint256 internal ENTRY_PRICE = 2 ether;
    uint256 internal MIN_ENTRIES = 10;
    uint256 internal DEADLINE_FROM_NOW = 86_400;
    bytes internal CHECK_DATA = abi.encode(0, 500);

    // Network configs
    uint64 internal creationFeeValue = 0 ether;
    uint64 internal poolFeePercentage = 0.05 ether;
    bytes32 internal chainlinkKeyHash = 0x787d74caea10b2b357790d5b5247c2f63d1d91572a9846f780606e4d953677ae;
    uint256 internal chainlinkSubscriptionId = 420;

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
            creationFeeValue,
            poolFeePercentage,
            address(vrfCoordinator),
            chainlinkKeyHash,
            chainlinkSubscriptionId
        );

        // Add RafflFactory as Consumer
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

    function createNewRaffle(address creator, uint256 creationFee) public returns (Raffl raffle) {
        vm.deal(creator, creationFee);
        vm.prank(creator);
        raffle = Raffl(
            rafflFactory.createRaffle{ value: creationFee }(
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

    function makeUserAcquireFreeEntries(Raffl raffl, address user) public {
        vm.prank(user);
        raffl.buyEntries(1);
    }

    function makeUserBuyEntries(Raffl raffl, address user, uint256 amount) public {
        uint256 entryPrice = raffl.entryPrice();
        uint256 value = entryPrice * amount;
        vm.deal(user, value);
        vm.prank(user);
        raffl.buyEntries{ value: value }(amount);
    }

    function makeUserBuyEntries(Raffl raffl, ERC20Mock entryAsset, address user, uint256 amount) public {
        uint256 entryPrice = raffl.entryPrice();
        uint256 value = entryPrice * amount;
        deal(address(entryAsset), user, value);
        vm.startPrank(user);
        entryAsset.approve(address(raffl), value);
        raffl.buyEntries(amount);
        vm.stopPrank();
    }

    function findActiveRaffle(Raffl raffl)
        public
        view
        returns (address activeRaffle, uint256 activeRaffleIdx, bool success)
    {
        RafflFactory.ActiveRaffle[] memory activeRaffles = rafflFactory.activeRaffles();

        for (uint256 i = 0; i < activeRaffles.length; i++) {
            if (activeRaffles[i].raffle == address(raffl)) {
                activeRaffle = address(raffl);
                activeRaffleIdx = i;
                success = true;

                break;
            }
        }
    }

    function performUpkeepOnActiveRaffl(Raffl raffl) public returns (uint256 requestId) {
        (address activeRaffle, uint256 activeRafflIdx,) = findActiveRaffle(raffl);

        bytes memory performData = abi.encode(activeRaffle, activeRafflIdx);

        bool criteriaMet = raffl.criteriaMet();

        vm.recordLogs();
        rafflFactory.performUpkeep(performData);
        Vm.Log[] memory entries = vm.getRecordedLogs();

        if (criteriaMet) {
            assertEq(entries.length, 2);
            assertEq(entries[1].topics[0], keccak256("DeadlineSuccessCriteria(uint256,uint256,uint256)"));
            // DeadlineSuccessCriteria(uint256 indexed requestId, uint256 entries, uint256 minEntries);
            requestId = uint256(entries[1].topics[1]);
        } else {
            assertEq(entries.length, 1);
            assertEq(entries[0].topics[0], keccak256("DeadlineFailedCriteria(uint256,uint256)"));
        }
    }

    function fullfillVRFOnActiveAndEligibleRaffle(
        uint256 requestId,
        address consumer
    )
        public
        returns (address winnerUser)
    {
        vm.recordLogs();
        vrfCoordinator.fulfillRandomWords(requestId, consumer);
        Vm.Log[] memory entries = vm.getRecordedLogs();

        if (entries.length >= 2) {
            assertEq(entries[entries.length - 2].topics[0], keccak256("DrawSuccess(uint256,uint256,address,uint256)"));
            // DrawSuccess(uint256 indexed requestId, uint256 winnerEntry, address user, uint256 entries)
            (, winnerUser,) = abi.decode(entries[entries.length - 2].data, (uint256, address, uint256));
        } else {
            revert("RandomWordsFulfilled failed executing `disperseRewards`");
        }
    }

    function processRaffleWithoutCriteriaMet(Raffl raffl) internal {
        if (raffl.criteriaMet()) revert("Refunds available when criteria not met.");

        vm.warp(raffl.deadline());
        performUpkeepOnActiveRaffl(raffl);

        assertTrue(raffl.gameStatus() == IRaffl.GameStatus.FailedDraw);
    }
}
