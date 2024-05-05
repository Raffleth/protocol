// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.25;

import { Raffl } from "../../../src/Raffl.sol";
import { IFeeManager } from "../../../src/interfaces/IFeeManager.sol";
import { Errors } from "../../../src/libraries/RafflFactoryErrors.sol";

import { Common } from "../../utils/Common.sol";

contract RafflCustomPoolFeeTest is Common {
    Raffl raffl;
    address someUser = address(200);

    function setUp() public virtual {
        fundAndSetPrizes(someUser);

        // Create the raffle
        raffl = createNewRaffle(someUser);

        // Purchase entries
        makeUserBuyEntries(raffl, userA, 5);
        makeUserBuyEntries(raffl, userB, 6);
        makeUserBuyEntries(raffl, userC, 7);
        makeUserBuyEntries(raffl, userD, 8);

        // Forward time to deadline
        vm.warp(raffl.deadline());
    }

    function proposeAndExecutePoolFeeChange(address user, uint64 newPoolFee) internal {
        vm.prank(feeCollector);
        rafflFactory.scheduleCustomPoolFee(user, newPoolFee);
        skip(1 hours);
    }

    function proposeAndExecutePoolFeeToggleOff(address user) internal {
        vm.prank(feeCollector);
        rafflFactory.toggleCustomPoolFee(user, false);
        skip(1 hours);
    }

    /// @dev should not allow pool fee change if the sender is not the fee collector
    function test_RevertIfCustomPoolFeeChangeNotByFeeCollector() public {
        uint64 newCustomPoolFee = 0.075 ether;

        vm.prank(attacker);
        vm.expectRevert(Errors.NotFeeCollector.selector);
        rafflFactory.scheduleCustomPoolFee(someUser, newCustomPoolFee);
    }

    /// @dev should not allow pool fee toggle if the sender is not the fee collector
    function test_RevertIfCustomPoolFeeToggleNotByFeeCollector() public {
        vm.prank(attacker);
        vm.expectRevert(Errors.NotFeeCollector.selector);
        rafflFactory.toggleCustomPoolFee(someUser, false);
    }

    /// @dev can set a pool fee for a specific user
    function test_CanSetCustomPoolFeePerUser() public view {
        uint64 globalPoolFee = rafflFactory.globalPoolFee();
        (, uint64 currentUserPoolFe) = rafflFactory.poolFeeData(someUser);

        assertEq(globalPoolFee, currentUserPoolFe);

        uint64 newCustomPoolFee = 0.01 ether;
        assertNotEq(globalPoolFee, newCustomPoolFee);
    }

    /// @dev can toggle off a pool fee for a specific user (defaults to global)
    function test_CanToggleOffCustomPoolFeePerUser() public {
        uint64 globalPoolFee = rafflFactory.globalPoolFee();
        (, uint64 currentUserPoolFee) = rafflFactory.poolFeeData(someUser);
        assertEq(currentUserPoolFee, globalPoolFee);

        proposeAndExecutePoolFeeChange(someUser, 0.02 ether);
        (, currentUserPoolFee) = rafflFactory.poolFeeData(someUser);
        assertNotEq(currentUserPoolFee, globalPoolFee);

        proposeAndExecutePoolFeeToggleOff(someUser);
        (, currentUserPoolFee) = rafflFactory.poolFeeData(someUser);
        assertEq(globalPoolFee, currentUserPoolFee);
    }

    /// @dev collects the custoom pool fee from the raffle success draw
    function test_TransferPoolToCreatorAfterFees() public {
        // Set a custom fee
        uint64 newRafflPoolFeePercentage = 0.01 ether;
        proposeAndExecutePoolFeeChange(someUser, newRafflPoolFeePercentage);

        // Check initial balances
        uint256 initialFeeCollectorBalance = feeCollector.balance;
        uint256 initialRaffleCreatorBalance = someUser.balance;

        // Get the total pool
        uint256 totalPool = address(raffl).balance;

        // Make the draw
        if (!raffl.criteriaMet()) revert("Criteria not met.");
        uint256 requestId = performUpkeepOnActiveRaffl(raffl);
        fullfillVRFOnActiveAndEligibleRaffle(requestId, address(rafflFactory));

        // Check final balances
        uint256 finalFeeCollectorBalance = feeCollector.balance;
        uint256 finalRaffleCreatorBalance = someUser.balance;

        // Transfers
        uint256 creatorReceived = finalRaffleCreatorBalance - initialRaffleCreatorBalance;
        uint256 feeCollectorReceived = finalFeeCollectorBalance - initialFeeCollectorBalance;

        // Check rewards received
        uint256 expectedFeeTaken = (totalPool * newRafflPoolFeePercentage) / 1 ether;
        assertEq(creatorReceived, totalPool - expectedFeeTaken);
        assertEq(feeCollectorReceived, expectedFeeTaken);
    }
}
