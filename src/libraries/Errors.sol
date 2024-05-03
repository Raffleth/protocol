// SPDX-License-Identifier: None
// Raffl Contracts (last updated v1.0.0) (Errors.sol)
pragma solidity ^0.8.25;

/// @title RafflFactory Errors Library
library RafflFactoryErrors {
    error AddressCanNotBeZero();
    error FailedToDeploy();
    error FeeOutOfRange();
    error NotFeeCollector();
    error PrizesIsEmpty();
    error DeadlineIsNotFuture();
    error UnsuccessfulTransferFromPrize();
    error ERC20PrizeAmountIsZero();
    error UpkeepConditionNotMet();
    error NoActiveRaffles();
    error InvalidLowerAndUpperBounds();
    error ActiveRaffleIndexOutOfBounds();
    error ProposalNotReady();
    error FeeAlreadySet();
    error NotARaffle();
}

/// @title Raffl Errors Library
library RafflErrors {
    error OnlyFactoryAllowed();
    error OnlyCreatorAllowed();
    error EntryQuantityRequired();
    error EntriesPurchaseClosed();
    error EntriesPurchaseInvalidValue();
    error RefundsOnlyAllowedOnFailedDraw();
    error UserWithoutEntries();
    error PrizesAlreadyRefunded();
    error MaxEntriesReached();
    error WithoutRefunds();
    error TokenGateRestriction();
    error FetchTokenBalanceFail();
    error RefundPenalityRequired();
}
