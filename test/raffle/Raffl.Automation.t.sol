// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.25;

import { VRFV2PlusClient } from "@chainlink/contracts/src/v0.8/vrf/dev/libraries/VRFV2PlusClient.sol";

import { Raffl } from "../../src/Raffl.sol";
import { RafflFactory } from "../../src/RafflFactory.sol";
import { IRaffl } from "../../src/interfaces/IRaffl.sol";
import { Errors } from "../../src/libraries/RafflFactoryErrors.sol";

import { Common } from "../utils/Common.sol";
import { VRFCoordinatorV2PlusMock } from "../mocks/VRFCoordinatorV2PlusMock.sol";

contract RafflAutomationTest is Common {
    Raffl public raffl;

    function setUp() public virtual {
        fundAndSetPrizes(raffleCreator);

        raffl = createNewRaffle(raffleCreator);
    }

    /// @dev should add the created raffle in the `_activeRaffles` array
    function test_AddNewActiveRaffle() public {
        makeUserBuyEntries(raffl, userA, 5);
        makeUserBuyEntries(raffl, userB, 1);
        makeUserBuyEntries(raffl, userC, 1);
        makeUserBuyEntries(raffl, userD, 3);

        RafflFactory.ActiveRaffle[] memory finalActiveRaffles = rafflFactory.activeRaffles();
        RafflFactory.ActiveRaffle memory lastActiveRaffle = finalActiveRaffles[finalActiveRaffles.length - 1];

        assertEq(finalActiveRaffles.length, 1);
        assertEq(lastActiveRaffle.raffle, address(raffl));
        assertEq(lastActiveRaffle.deadline, raffl.deadline());
    }

    /// @dev should be able to call checkUpkeep
    function test_ShouldCallCheckUpKeep() public view {
        (bool upkeepNeeded,) = rafflFactory.checkUpkeep(CHECK_DATA);
        assertFalse(upkeepNeeded);
    }

    /// @dev should not be able to call performUpkeep with an incorrect raffle address
    function test_RevertIf_PerformsUpkeepWithIncorrectRaffle() public {
        bytes memory performData = abi.encode(attacker, 500);

        vm.expectRevert(Errors.UpkeepConditionNotMet.selector);
        vm.prank(admin);
        rafflFactory.performUpkeep(performData);
    }

    /// @dev should not be able to call performUpkeep for a raffle without deadline passed
    function test_RevertIf_PerformsUpkeepWithPendingRaffle() public {
        (address activeRaffle, uint256 activeRafflIdx,) = findActiveRaffle(raffl);

        bytes memory performData = abi.encode(activeRaffle, activeRafflIdx);

        vm.expectRevert(Errors.UpkeepConditionNotMet.selector);
        vm.prank(admin);
        rafflFactory.performUpkeep(performData);
    }

    /// @dev should be able to call performUpkeep after deadline is met
    function test_CanCallPerformUpkeepWithRafflReady() public {
        makeUserBuyEntries(raffl, userA, raffl.minEntries());
        vm.warp(raffl.deadline() + 1);

        assertTrue(raffl.criteriaMet());
        assertTrue(raffl.deadlineExpired());

        (address activeRaffle, uint256 activeRafflIdx,) = findActiveRaffle(raffl);

        bytes memory performData = abi.encode(activeRaffle, activeRafflIdx);

        // Check 3 topics and sender, but do not check data
        uint256 nextRequestId = vrfCoordinator.nextRequestId();
        vm.expectEmit(true, true, true, false, address(rafflFactory.s_vrfCoordinator()));
        emit VRFCoordinatorV2PlusMock.RandomWordsRequested(
            chainlinkKeyHash,
            nextRequestId,
            0,
            rafflFactory.subscriptionId(),
            3,
            0,
            1,
            VRFV2PlusClient._argsToBytes(VRFV2PlusClient.ExtraArgsV1({ nativePayment: false })),
            address(rafflFactory)
        );

        // Check topic, data and sender,
        vm.expectEmit(true, false, false, true, address(raffl));
        emit IRaffl.DeadlineSuccessCriteria(nextRequestId, raffl.entries(), raffl.minEntries());

        rafflFactory.performUpkeep(performData);

        assertTrue(raffl.upkeepPerformed());
    }

    /// @dev should remove the created raffle from the `_activeRaffles` array after performUpkeep
    function test_RemovesActiveRaffleAfterPerformUpkeep() public {
        makeUserBuyEntries(raffl, userA, raffl.minEntries());
        vm.warp(raffl.deadline() + 1);

        performUpkeepOnActiveRaffl(raffl);

        (address activeRaffle, uint256 activeRafflIdx, bool success) = findActiveRaffle(raffl);
        assertEq(activeRaffle, address(0));
        assertEq(activeRafflIdx, 0);
        assertFalse(success);
    }
}
