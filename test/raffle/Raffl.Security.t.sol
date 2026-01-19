// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.33;

import { Raffl } from "../../src/Raffl.sol";
import { IRaffl } from "../../src/interfaces/IRaffl.sol";
import { Errors } from "../../src/libraries/RafflErrors.sol";

import { Common } from "../utils/Common.sol";
import { ERC20Mock } from "../mocks/ERC20Mock.sol";
import { ERC721Mock } from "../mocks/ERC721Mock.sol";
import { ERC20 } from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import { ERC721 } from "@openzeppelin/contracts/token/ERC721/ERC721.sol";

/// @dev Malicious ERC20 that attempts reentrancy on transfer
contract ReentrantERC20 is ERC20 {
    Raffl public target;
    bool public attacking;
    uint256 public attackCount;

    constructor() ERC20("Reentrant", "REENT") { }

    function mint(address to, uint256 amount) external {
        _mint(to, amount);
    }

    function setTarget(address _target) external {
        target = Raffl(_target);
    }

    function transfer(address to, uint256 amount) public override returns (bool) {
        if (attacking && attackCount < 3) {
            attackCount++;
            // Try to re-enter disperseRewards
            try target.disperseRewards() { } catch { }
        }
        return super.transfer(to, amount);
    }

    function startAttack() external {
        attacking = true;
    }
}

/// @dev Malicious ERC20 that attempts reentrancy on refund
contract ReentrantRefundERC20 is ERC20 {
    Raffl public target;
    address public attacker;
    bool public attacking;
    uint256 public attackCount;

    constructor() ERC20("ReentrantRefund", "REENTRF") { }

    function mint(address to, uint256 amount) external {
        _mint(to, amount);
    }

    function setTarget(address _target, address _attacker) external {
        target = Raffl(_target);
        attacker = _attacker;
    }

    function transfer(address to, uint256 amount) public override returns (bool) {
        if (attacking && attackCount < 3 && to == attacker) {
            attackCount++;
            // Try to re-enter refundEntries
            try target.refundEntries(attacker) { } catch { }
        }
        return super.transfer(to, amount);
    }

    function startAttack() external {
        attacking = true;
    }
}

/// @dev Malicious ERC721 that attempts reentrancy
contract ReentrantERC721 is ERC721 {
    Raffl public target;
    bool public attacking;
    uint256 public attackCount;

    constructor() ERC721("ReentrantNFT", "REENFT") { }

    function mint(address to, uint256 tokenId) external {
        _mint(to, tokenId);
    }

    function setTarget(address _target) external {
        target = Raffl(_target);
    }

    function transferFrom(address from, address to, uint256 tokenId) public override {
        if (attacking && attackCount < 3) {
            attackCount++;
            try target.disperseRewards() { } catch { }
        }
        super.transferFrom(from, to, tokenId);
    }

    function startAttack() external {
        attacking = true;
    }
}

/// @dev Contract that attempts reentrancy when receiving ETH
contract ReentrantETHReceiver {
    Raffl public target;
    uint256 public attackCount;
    bool public attacking;

    function setTarget(address _target) external {
        target = Raffl(_target);
    }

    function startAttack() external {
        attacking = true;
    }

    receive() external payable {
        if (attacking && attackCount < 3) {
            attackCount++;
            try target.disperseRewards() { } catch { }
        }
    }
}

/// @dev Contract that attempts reentrancy on refund via ETH receive
contract ReentrantRefundReceiver {
    Raffl public target;
    uint256 public attackCount;
    bool public attacking;

    function setTarget(address _target) external {
        target = Raffl(_target);
    }

    function startAttack() external {
        attacking = true;
    }

    function buyEntries(Raffl raffl, uint256 quantity) external payable {
        raffl.buyEntries{ value: msg.value }(quantity);
    }

    receive() external payable {
        if (attacking && attackCount < 3) {
            attackCount++;
            try target.refundEntries(address(this)) { } catch { }
        }
    }
}

/// @dev ERC20 that returns false on transfer (non-reverting failure)
contract FailingERC20 is ERC20 {
    bool public shouldFail;

    constructor() ERC20("Failing", "FAIL") { }

    function mint(address to, uint256 amount) external {
        _mint(to, amount);
    }

    function setShouldFail(bool _shouldFail) external {
        shouldFail = _shouldFail;
    }

    function transfer(address to, uint256 amount) public override returns (bool) {
        if (shouldFail) {
            return false;
        }
        return super.transfer(to, amount);
    }

    function transferFrom(address from, address to, uint256 amount) public override returns (bool) {
        if (shouldFail) {
            return false;
        }
        return super.transferFrom(from, to, amount);
    }
}

contract RafflSecurityTest is Common {
    Raffl raffl;

    function setUp() public virtual {
        fundAndSetPrizes(raffleCreator);
    }

    /*//////////////////////////////////////////////////////////////
                    REENTRANCY ON disperseRewards
    //////////////////////////////////////////////////////////////*/

    /// @dev Should prevent reentrancy attack via malicious ERC20 prize during disperseRewards
    function test_PreventReentrancyViaERC20Prize() public {
        ReentrantERC20 maliciousToken = new ReentrantERC20();
        maliciousToken.mint(raffleCreator, 100 ether);

        vm.startPrank(raffleCreator);
        maliciousToken.approve(address(rafflFactory), 100 ether);

        IRaffl.Prize[] memory maliciousPrizes = new IRaffl.Prize[](1);
        maliciousPrizes[0] = IRaffl.Prize(address(maliciousToken), IRaffl.AssetType.ERC20, 100 ether);

        raffl = Raffl(
            rafflFactory.createRaffle(
                address(0),
                ENTRY_PRICE,
                MIN_ENTRIES,
                block.timestamp + DEADLINE_FROM_NOW,
                maliciousPrizes,
                tokenGates,
                extraRecipient
            )
        );
        vm.stopPrank();

        maliciousToken.setTarget(address(raffl));

        makeUserBuyEntries(raffl, userA, MIN_ENTRIES);
        vm.warp(raffl.deadline());
        uint256 requestId = performUpkeepOnActiveRaffl(raffl);

        // VRF fulfillment
        vm.recordLogs();
        vrfCoordinator.fulfillRandomWords(requestId, address(rafflFactory));

        // Start attack before dispersal
        maliciousToken.startAttack();

        // Dispersal should complete without reentrancy issues
        raffl.disperseRewards();

        // Verify state is correct (only dispersed once)
        assertEq(uint8(raffl.gameStatus()), uint8(IRaffl.GameStatus.SuccessDraw));
        assertEq(maliciousToken.attackCount(), 1); // Attack tried but prevented
    }

    /// @dev Should prevent reentrancy attack via malicious ERC721 prize during disperseRewards
    function test_PreventReentrancyViaERC721Prize() public {
        ReentrantERC721 maliciousNFT = new ReentrantERC721();
        maliciousNFT.mint(raffleCreator, 1);

        vm.startPrank(raffleCreator);
        maliciousNFT.approve(address(rafflFactory), 1);

        IRaffl.Prize[] memory maliciousPrizes = new IRaffl.Prize[](1);
        maliciousPrizes[0] = IRaffl.Prize(address(maliciousNFT), IRaffl.AssetType.ERC721, 1);

        raffl = Raffl(
            rafflFactory.createRaffle(
                address(0),
                ENTRY_PRICE,
                MIN_ENTRIES,
                block.timestamp + DEADLINE_FROM_NOW,
                maliciousPrizes,
                tokenGates,
                extraRecipient
            )
        );
        vm.stopPrank();

        maliciousNFT.setTarget(address(raffl));

        makeUserBuyEntries(raffl, userA, MIN_ENTRIES);
        vm.warp(raffl.deadline());
        uint256 requestId = performUpkeepOnActiveRaffl(raffl);

        vm.recordLogs();
        vrfCoordinator.fulfillRandomWords(requestId, address(rafflFactory));

        maliciousNFT.startAttack();

        raffl.disperseRewards();

        assertEq(uint8(raffl.gameStatus()), uint8(IRaffl.GameStatus.SuccessDraw));
    }

    /// @dev Should prevent reentrancy attack via malicious winner receiving ETH
    function test_PreventReentrancyViaETHReceiver() public {
        ReentrantETHReceiver attacker = new ReentrantETHReceiver();

        raffl = createNewRaffle(raffleCreator);
        attacker.setTarget(address(raffl));

        // Attacker buys entries
        uint256 entryPrice = raffl.entryPrice();
        vm.deal(address(attacker), entryPrice * MIN_ENTRIES);
        vm.prank(address(attacker));
        raffl.buyEntries{ value: entryPrice * MIN_ENTRIES }(MIN_ENTRIES);

        vm.warp(raffl.deadline());
        uint256 requestId = performUpkeepOnActiveRaffl(raffl);

        vm.recordLogs();
        vrfCoordinator.fulfillRandomWords(requestId, address(rafflFactory));

        // If attacker is the winner, they'll try reentrancy when receiving ETH
        attacker.startAttack();

        // This should complete without reentrancy
        raffl.disperseRewards();

        assertEq(uint8(raffl.gameStatus()), uint8(IRaffl.GameStatus.SuccessDraw));
    }

    /*//////////////////////////////////////////////////////////////
                    REENTRANCY ON refundEntries
    //////////////////////////////////////////////////////////////*/

    /// @dev Should prevent reentrancy attack via malicious ERC20 during refund
    function test_PreventReentrancyOnERC20Refund() public {
        ReentrantRefundERC20 maliciousToken = new ReentrantRefundERC20();
        maliciousToken.mint(attacker, ENTRY_PRICE * 5);

        vm.startPrank(raffleCreator);

        IRaffl.Prize[] memory normalPrizes = new IRaffl.Prize[](1);
        normalPrizes[0] = IRaffl.Prize(address(testERC20), IRaffl.AssetType.ERC20, ERC20_AMOUNT);
        testERC20.approve(address(rafflFactory), ERC20_AMOUNT);

        raffl = Raffl(
            rafflFactory.createRaffle(
                address(maliciousToken), // Use malicious token for entries
                ENTRY_PRICE,
                MIN_ENTRIES,
                block.timestamp + DEADLINE_FROM_NOW,
                normalPrizes,
                tokenGates,
                extraRecipient
            )
        );
        vm.stopPrank();

        // Attacker buys entries
        vm.startPrank(attacker);
        maliciousToken.approve(address(raffl), ENTRY_PRICE * 5);
        raffl.buyEntries(5);
        vm.stopPrank();

        maliciousToken.setTarget(address(raffl), attacker);

        // Process failed draw (not enough entries)
        vm.warp(raffl.deadline());
        performUpkeepOnActiveRaffl(raffl);

        // Start attack
        maliciousToken.startAttack();

        // Refund should complete without reentrancy
        vm.prank(attacker);
        raffl.refundEntries(attacker);

        // Verify attacker was marked as refunded
        assertTrue(raffl.userRefund(attacker));
    }

    /// @dev Should prevent reentrancy attack via ETH receive during refund
    function test_PreventReentrancyOnETHRefund() public {
        ReentrantRefundReceiver attackerContract = new ReentrantRefundReceiver();

        raffl = createNewRaffle(raffleCreator);
        attackerContract.setTarget(address(raffl));

        // Attacker buys entries
        uint256 entryPrice = raffl.entryPrice();
        vm.deal(address(attackerContract), entryPrice * 5);
        attackerContract.buyEntries{ value: entryPrice * 5 }(raffl, 5);

        // Process failed draw
        vm.warp(raffl.deadline());
        performUpkeepOnActiveRaffl(raffl);

        // Start attack
        attackerContract.startAttack();

        // Refund should complete without reentrancy
        raffl.refundEntries(address(attackerContract));

        assertTrue(raffl.userRefund(address(attackerContract)));
    }

    /*//////////////////////////////////////////////////////////////
                    MALICIOUS TOKEN TESTS
    //////////////////////////////////////////////////////////////*/

    /// @dev Should handle ERC20 that returns false on transfer
    function test_HandleFailingERC20Transfer() public {
        FailingERC20 failingToken = new FailingERC20();
        failingToken.mint(raffleCreator, 100 ether);

        vm.startPrank(raffleCreator);
        failingToken.approve(address(rafflFactory), 100 ether);

        IRaffl.Prize[] memory failingPrizes = new IRaffl.Prize[](1);
        failingPrizes[0] = IRaffl.Prize(address(failingToken), IRaffl.AssetType.ERC20, 100 ether);

        raffl = Raffl(
            rafflFactory.createRaffle(
                address(0),
                ENTRY_PRICE,
                MIN_ENTRIES,
                block.timestamp + DEADLINE_FROM_NOW,
                failingPrizes,
                tokenGates,
                extraRecipient
            )
        );
        vm.stopPrank();

        makeUserBuyEntries(raffl, userA, MIN_ENTRIES);
        vm.warp(raffl.deadline());
        uint256 requestId = performUpkeepOnActiveRaffl(raffl);

        vm.recordLogs();
        vrfCoordinator.fulfillRandomWords(requestId, address(rafflFactory));

        // Make the token fail transfers
        failingToken.setShouldFail(true);

        // Dispersal should revert
        vm.expectRevert();
        raffl.disperseRewards();
    }

    /*//////////////////////////////////////////////////////////////
                    ACCESS CONTROL TESTS
    //////////////////////////////////////////////////////////////*/

    /// @dev Should prevent non-factory from calling setSuccessCriteria
    function test_RevertIf_NonFactoryCallsSetSuccessCriteria() public {
        raffl = createNewRaffle(raffleCreator);

        vm.expectRevert(Errors.OnlyFactoryAllowed.selector);
        vm.prank(attacker);
        raffl.setSuccessCriteria(123);
    }

    /// @dev Should prevent non-factory from calling setFailedCriteria
    function test_RevertIf_NonFactoryCallsSetFailedCriteria() public {
        raffl = createNewRaffle(raffleCreator);

        vm.expectRevert(Errors.OnlyFactoryAllowed.selector);
        vm.prank(attacker);
        raffl.setFailedCriteria();
    }

    /// @dev Should prevent non-factory from calling setWinner
    function test_RevertIf_NonFactoryCallsSetWinner() public {
        raffl = createNewRaffle(raffleCreator);

        makeUserBuyEntries(raffl, userA, MIN_ENTRIES);
        vm.warp(raffl.deadline());
        performUpkeepOnActiveRaffl(raffl);

        vm.expectRevert(Errors.OnlyFactoryAllowed.selector);
        vm.prank(attacker);
        raffl.setWinner(123, 456);
    }

    /// @dev Should prevent non-creator from calling refundPrizes
    function test_RevertIf_NonCreatorCallsRefundPrizes() public {
        raffl = createNewRaffle(raffleCreator);

        makeUserBuyEntries(raffl, userA, 1);
        vm.warp(raffl.deadline());
        performUpkeepOnActiveRaffl(raffl);

        vm.expectRevert(Errors.OnlyCreatorAllowed.selector);
        vm.prank(attacker);
        raffl.refundPrizes();
    }

    /*//////////////////////////////////////////////////////////////
                    STATE MANIPULATION TESTS
    //////////////////////////////////////////////////////////////*/

    /// @dev Should prevent double dispersal
    function test_RevertIf_DoubleDispersal() public {
        raffl = createNewRaffle(raffleCreator);

        makeUserBuyEntries(raffl, userA, MIN_ENTRIES);
        vm.warp(raffl.deadline());
        uint256 requestId = performUpkeepOnActiveRaffl(raffl);

        vm.recordLogs();
        vrfCoordinator.fulfillRandomWords(requestId, address(rafflFactory));

        // First dispersal
        raffl.disperseRewards();

        // Second dispersal should fail
        vm.expectRevert(Errors.WinnerNotDrawn.selector);
        raffl.disperseRewards();
    }

    /// @dev Should prevent dispersal before winner is drawn
    function test_RevertIf_DispersalBeforeWinnerDrawn() public {
        raffl = createNewRaffle(raffleCreator);

        makeUserBuyEntries(raffl, userA, MIN_ENTRIES);

        // Try to disperse before deadline
        vm.expectRevert(Errors.WinnerNotDrawn.selector);
        raffl.disperseRewards();

        // After deadline but before VRF
        vm.warp(raffl.deadline());
        performUpkeepOnActiveRaffl(raffl);

        vm.expectRevert(Errors.WinnerNotDrawn.selector);
        raffl.disperseRewards();
    }

    /// @dev Should prevent double refund
    function test_RevertIf_DoubleRefund() public {
        raffl = createNewRaffle(raffleCreator);

        makeUserBuyEntries(raffl, userA, 5);
        vm.warp(raffl.deadline());
        performUpkeepOnActiveRaffl(raffl);

        // First refund
        raffl.refundEntries(userA);

        // Second refund should fail
        vm.expectRevert(Errors.UserAlreadyRefunded.selector);
        raffl.refundEntries(userA);
    }

    /// @dev Should prevent double prize refund
    function test_RevertIf_DoublePrizeRefund() public {
        raffl = createNewRaffle(raffleCreator);

        makeUserBuyEntries(raffl, userA, 1);
        vm.warp(raffl.deadline());
        performUpkeepOnActiveRaffl(raffl);

        // First prize refund
        vm.prank(raffleCreator);
        raffl.refundPrizes();

        // Second prize refund should fail
        vm.expectRevert(Errors.PrizesAlreadyRefunded.selector);
        vm.prank(raffleCreator);
        raffl.refundPrizes();
    }

    /*//////////////////////////////////////////////////////////////
                    ENTRY PURCHASE AFTER STATES
    //////////////////////////////////////////////////////////////*/

    /// @dev Should prevent entry purchase after failed draw
    function test_RevertIf_EntryAfterFailedDraw() public {
        raffl = createNewRaffle(raffleCreator);

        makeUserBuyEntries(raffl, userA, 1);
        vm.warp(raffl.deadline());
        performUpkeepOnActiveRaffl(raffl);

        assertEq(uint8(raffl.gameStatus()), uint8(IRaffl.GameStatus.FailedDraw));

        uint256 entryPrice = raffl.entryPrice();
        vm.deal(userB, entryPrice);

        vm.expectRevert(Errors.EntriesPurchaseClosed.selector);
        vm.prank(userB);
        raffl.buyEntries{ value: entryPrice }(1);
    }

    /// @dev Should prevent entry purchase after draw started
    function test_RevertIf_EntryAfterDrawStarted() public {
        raffl = createNewRaffle(raffleCreator);

        makeUserBuyEntries(raffl, userA, MIN_ENTRIES);
        vm.warp(raffl.deadline());
        performUpkeepOnActiveRaffl(raffl);

        assertEq(uint8(raffl.gameStatus()), uint8(IRaffl.GameStatus.DrawStarted));

        uint256 entryPrice = raffl.entryPrice();
        vm.deal(userB, entryPrice);

        vm.expectRevert(Errors.EntriesPurchaseClosed.selector);
        vm.prank(userB);
        raffl.buyEntries{ value: entryPrice }(1);
    }

    /*//////////////////////////////////////////////////////////////
                    REFUND STATE TESTS
    //////////////////////////////////////////////////////////////*/

    /// @dev Should prevent refund when not in FailedDraw state
    function test_RevertIf_RefundWhenNotFailedDraw() public {
        raffl = createNewRaffle(raffleCreator);

        makeUserBuyEntries(raffl, userA, MIN_ENTRIES);

        // Before deadline (Initialized state)
        vm.expectRevert(Errors.RefundsOnlyAllowedOnFailedDraw.selector);
        raffl.refundEntries(userA);

        // After deadline + VRF (DrawStarted state)
        vm.warp(raffl.deadline());
        performUpkeepOnActiveRaffl(raffl);

        vm.expectRevert(Errors.RefundsOnlyAllowedOnFailedDraw.selector);
        raffl.refundEntries(userA);
    }

    /// @dev Should prevent refund for user without entries
    function test_RevertIf_RefundWithoutEntries() public {
        raffl = createNewRaffle(raffleCreator);

        makeUserBuyEntries(raffl, userA, 1);
        vm.warp(raffl.deadline());
        performUpkeepOnActiveRaffl(raffl);

        // userB has no entries
        vm.expectRevert(Errors.UserWithoutEntries.selector);
        raffl.refundEntries(userB);
    }
}
