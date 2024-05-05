// SPDX-License-Identifier: None
// Raffl Protocol (last updated v1.0.0) (Raffl.sol)
pragma solidity ^0.8.25;

import { ReentrancyGuardUpgradeable } from "@openzeppelin/contracts-upgradeable/utils/ReentrancyGuardUpgradeable.sol";

import { TokenLib } from "./libraries/TokenLib.sol";
import { Errors } from "./libraries/RafflErrors.sol";

import { IRaffl } from "./interfaces/IRaffl.sol";
import { IFeeManager } from "./interfaces/IFeeManager.sol";

/*
                                                                       
  _____            ______ ______ _      
 |  __ \     /\   |  ____|  ____| |     
 | |__) |   /  \  | |__  | |__  | |     
 |  _  /   / /\ \ |  __| |  __| | |     
 | | \ \  / ____ \| |    | |    | |____ 
 |_|  \_\/_/    \_\_|    |_|    |______|                               
                                                                       
 */

/// @title Raffl
/// @author JA <@ubinatus>
/// @notice Raffl is a decentralized platform built on the Ethereum blockchain, allowing users to create and participate
/// in raffles/lotteries with complete transparency, security, and fairness.
contract Raffl is ReentrancyGuardUpgradeable, IRaffl {
    /**
     *
     * STATE
     *
     */
    /// @dev Address of the RafflFactory
    address public factory;
    /// @dev User address that created the Raffl
    address public creator;
    /// @dev Prizes contained in the Raffl
    Prize[] public prizes;
    /// @dev Block timestamp for when the draw should be made and until entries are accepted
    uint256 public deadline;
    /// @dev Minimum number of entries required to execute the draw
    uint256 public minEntries;
    /// @dev Price of the entry to participate in the Raffl
    uint256 public entryPrice;
    /// @dev Address of the ERC20 entry token (if applicable)
    address public entryToken;
    /// @dev Array of token gates required for all participants to purchase entries.
    TokenGate[] public tokenGates;
    /// @dev Extra recipient to share the pooled funds.
    ExtraRecipient public extraRecipient;
    /// @dev Total number of entries acquired
    uint256 public entries;
    /// @dev Total pooled funds from entries acquisition
    uint256 public pool;
    /// @dev Maps an entry number to the owner address
    mapping(uint256 => address) public entriesMap; /* entry number */ /* user address */
    /// @dev Maps a user address to the total amount of entries owned
    mapping(address => uint256) public userEntriesMap; /* user address */ /* number of entries */
    /// @dev Whether the raffle is settled or not
    bool public settled;
    /// @dev Whether the prizes were refunded when criteria did not meet.
    bool public prizesRefunded;
    /// @dev Status of the Raffl game
    GameStatus public gameStatus;

    /// @dev Percentages and fees are calculated using 18 decimals where 1 ether is 100%.
    uint256 internal constant ONE = 1 ether;

    /// @notice The manager that deployed this contract which controls the values for `fee` and `feeCollector`.
    IFeeManager public manager;

    /**
     *
     * MODIFIERS
     *
     */
    modifier onlyFactory() {
        if (msg.sender != factory) revert Errors.OnlyFactoryAllowed();
        _;
    }

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    /**
     *
     * INITIALIZER
     *
     */

    //// @inheritdoc IRaffl
    function initialize(
        address _entryToken,
        uint256 _entryPrice,
        uint256 _minEntries,
        uint256 _deadline,
        address _creator,
        Prize[] calldata _prizes,
        TokenGate[] calldata _tokenGatesArray,
        ExtraRecipient calldata _extraRecipient
    )
        external
        override
        initializer
    {
        __ReentrancyGuard_init();

        entryToken = _entryToken;
        entryPrice = _entryPrice;
        minEntries = _minEntries;
        deadline = _deadline;
        creator = _creator;
        factory = msg.sender;
        manager = IFeeManager(msg.sender);

        for (uint256 i = 0; i < _prizes.length;) {
            prizes.push(_prizes[i]);

            unchecked {
                ++i;
            }
        }
        for (uint256 i = 0; i < _tokenGatesArray.length;) {
            tokenGates.push(_tokenGatesArray[i]);

            unchecked {
                ++i;
            }
        }
        extraRecipient = _extraRecipient;

        gameStatus = GameStatus.Initialized;

        emit RaffleInitialized();
    }

    /**
     *
     * METHODS
     *
     */

    /// @inheritdoc IRaffl
    function criteriaMet() external view override returns (bool) {
        return entries >= minEntries;
    }

    /// @inheritdoc IRaffl
    function deadlineExpired() external view override returns (bool) {
        return block.timestamp >= deadline;
    }

    /// @inheritdoc IRaffl
    function upkeepPerformed() external view override returns (bool) {
        return settled;
    }

    /// @notice Returns the current pool fee associated to this `Raffl`.
    function poolFeeData() external view returns (address, uint64) {
        return manager.poolFeeData(creator);
    }

    /// @inheritdoc IRaffl
    function buyEntries(uint256 quantity) external payable override nonReentrant {
        if (block.timestamp > deadline) revert Errors.EntriesPurchaseClosed();
        _ensureTokenGating(msg.sender);
        if (entryPrice > 0) {
            _purchaseEntry(quantity);
        } else {
            _purchaseFreeEntry();
        }
    }

    /// @inheritdoc IRaffl
    function refundEntries(address user) external override nonReentrant {
        if (gameStatus != GameStatus.FailedDraw) revert Errors.RefundsOnlyAllowedOnFailedDraw();
        if (userEntriesMap[user] == 0) revert Errors.UserWithoutEntries();
        if (entryPrice == 0) revert Errors.WithoutRefunds();
        uint256 userEntries = userEntriesMap[user];
        userEntriesMap[user] = 0;
        uint256 value = entryPrice * userEntries;
        if (entryToken != address(0)) {
            TokenLib.safeTransfer(entryToken, user, value);
        } else {
            payable(user).transfer(value);
        }
        emit EntriesRefunded(user, userEntries, value);
    }

    /// @inheritdoc IRaffl
    function refundPrizes() external payable override nonReentrant {
        if (gameStatus != GameStatus.FailedDraw) revert Errors.RefundsOnlyAllowedOnFailedDraw();
        if (creator != msg.sender) revert Errors.OnlyCreatorAllowed();
        if (prizesRefunded) revert Errors.PrizesAlreadyRefunded();

        prizesRefunded = true;
        _transferPrizes(creator);
        emit PrizesRefunded();
    }

    /**
     *
     * HELPERS
     *
     */

    /// @dev Transfers the prizes to the specified user.
    /// @param user The address of the user who will receive the prizes.
    function _transferPrizes(address user) private {
        uint256 len = prizes.length;
        for (uint256 i = 0; i < len;) {
            uint256 val = prizes[i].value;
            address asset = prizes[i].asset;
            if (prizes[i].assetType == AssetType.ERC20) {
                TokenLib.safeTransfer(asset, user, val);
            } else {
                TokenLib.safeTransferFrom(asset, address(this), user, val);
            }

            unchecked {
                ++i;
            }
        }
    }

    /// @dev Transfers the pool balance to the creator of the raffle, after deducting any fees.
    function _transferPool() private {
        uint256 balance =
            (entryToken != address(0)) ? TokenLib.balanceOf(entryToken, address(this)) : address(this).balance;

        if (balance > 0) {
            // Get feeData
            (address feeCollector, uint64 poolFeePercentage) = manager.poolFeeData(creator);
            uint256 fee = 0;

            // If fee is present, calculate it once and subtract from balance
            if (poolFeePercentage != 0) {
                fee = (balance * poolFeePercentage) / ONE;
                balance -= fee;
            }

            // Similar for extraRecipient.sharePercentage
            uint256 extraRecipientAmount = 0;
            if (extraRecipient.recipient != address(0) && extraRecipient.sharePercentage > 0) {
                extraRecipientAmount = (balance * extraRecipient.sharePercentage) / ONE;
                balance -= extraRecipientAmount;
            }

            if (entryToken != address(0)) {
                // Avoid checking the balance > 0 before each transfer
                if (fee > 0) {
                    TokenLib.safeTransfer(entryToken, feeCollector, fee);
                }
                if (extraRecipientAmount > 0) {
                    TokenLib.safeTransfer(entryToken, extraRecipient.recipient, extraRecipientAmount);
                }
                if (balance > 0) {
                    TokenLib.safeTransfer(entryToken, creator, balance);
                }
            } else {
                if (fee > 0) {
                    payable(feeCollector).transfer(fee);
                }
                if (extraRecipientAmount > 0) {
                    payable(extraRecipient.recipient).transfer(extraRecipientAmount);
                }
                if (balance > 0) {
                    payable(creator).transfer(balance);
                }
            }
        }
    }

    /// @dev Internal function to handle the purchase of entries with entry price greater than 0.
    /// @param quantity The quantity of entries to purchase.
    function _purchaseEntry(uint256 quantity) private {
        if (quantity == 0) revert Errors.EntryQuantityRequired();
        uint256 value = quantity * entryPrice;
        // Check if entryToken is a non-zero address, meaning ERC-20 is used for purchase
        if (entryToken != address(0)) {
            // Transfer the required amount of entryToken from user to contract
            // Assumes that the ERC-20 token follows the ERC-20 standard
            TokenLib.safeTransferFrom(entryToken, msg.sender, address(this), value);
        } else {
            // Check that the correct amount of Ether is sent
            if (msg.value != value) revert Errors.EntriesPurchaseInvalidValue();
        }

        // Increments the pool value
        pool += value;

        // Assigns the entry index to the user
        for (uint256 i = 0; i < quantity;) {
            entriesMap[entries + i] = msg.sender;

            unchecked {
                ++i;
            }
        }
        // Increments the total number of acquired entries for the raffle
        entries += quantity;

        // Increments the total number of acquired entries for the user
        userEntriesMap[msg.sender] += quantity;

        // Emits the `EntriesBought` event
        emit EntriesBought(msg.sender, quantity, value);
    }

    /// @dev Internal function to handle the purchase of free entries with entry price equal to 0.
    function _purchaseFreeEntry() private {
        // Allow up to one free entry per user
        if (userEntriesMap[msg.sender] == 1) revert Errors.MaxEntriesReached();
        // Assigns the entry index to the user
        entriesMap[entries] = msg.sender;

        // Increments the total number of acquired entries for the raffle
        ++entries;

        // Increments the total number of acquired entries for the user
        ++userEntriesMap[msg.sender];

        // Emits the `EntriesBought` event with zero `value`
        emit EntriesBought(msg.sender, 1, 0);
    }

    /// @notice Ensures that the user has all the requirements from the `tokenGates` array
    /// @param user Address of the user
    function _ensureTokenGating(address user) private view {
        uint256 len = tokenGates.length;
        for (uint256 i = 0; i < len;) {
            address token = tokenGates[i].token;
            uint256 amount = tokenGates[i].amount;

            // Extract the returned balance value
            uint256 balance = TokenLib.balanceOf(token, user);

            // Check if the balance meets the requirement
            if (balance < amount) {
                revert Errors.TokenGateRestriction();
            }

            unchecked {
                ++i;
            }
        }
    }

    /**
     *
     * FACTORY METHODS
     *
     */

    /// @inheritdoc IRaffl
    function setSuccessCriteria(uint256 requestId) external override onlyFactory {
        gameStatus = GameStatus.DrawStarted;
        emit DeadlineSuccessCriteria(requestId, entries, minEntries);
        settled = true;
    }

    /// @inheritdoc IRaffl
    function setFailedCriteria() external override onlyFactory {
        gameStatus = GameStatus.FailedDraw;
        emit DeadlineFailedCriteria(entries, minEntries);
        settled = true;
    }

    /// @inheritdoc IRaffl
    function disperseRewards(uint256 requestId, uint256 randomNumber) external override onlyFactory nonReentrant {
        uint256 winnerEntry = randomNumber % entries;
        address winnerUser = entriesMap[winnerEntry];

        _transferPrizes(winnerUser);
        _transferPool();

        gameStatus = GameStatus.SuccessDraw;

        emit DrawSuccess(requestId, winnerEntry, winnerUser, entries);
    }
}
