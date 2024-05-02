// SPDX-License-Identifier: None
// Raffl Contracts (last updated v1.0.0) (Raffl.sol)
pragma solidity ^0.8.25;

import { ReentrancyGuardUpgradeable } from "@openzeppelin/contracts-upgradeable/utils/ReentrancyGuardUpgradeable.sol";

import { TokenLib } from "./libraries/TokenLib.sol";
import { RafflErrors } from "./libraries/Errors.sol";

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

/**
 * @title Raffl
 * @author JA <@ubinatus>
 * @notice Raffl is a decentralized platform built on the Ethereum blockchain,
 * allowing users to create and participate in raffles/lotteries with complete transparency, security, and fairness.
 */
contract Raffl is ReentrancyGuardUpgradeable, IRaffl, IFeeManager {
    /**
     *
     * STATE
     *
     */
    address public factory;
    address public creator;
    Prize[] public prizes;
    uint256 public deadline;
    uint256 public minEntries;
    uint256 public entryPrice;
    address public entryToken;
    TokenGate[] public tokenGates;
    ExtraRecipient public extraRecipient;

    uint256 public entries;
    uint256 public pool;
    mapping(uint256 => address) public entriesMap; /* entry number */ /* user address */
    mapping(address => uint256) public userEntriesMap; /* user address */ /* number of entries */

    bool public settled;
    bool public prizesRefunded;

    GameStatus public gameStatus;

    /**
     * @dev Percentages and fees are calculated using 18 decimals where 1 ether is 100%.
     */
    uint256 internal constant ONE = 1 ether;

    /**
     * @notice The manager that deployed this contract which controls the values for `fee` and `feeCollector`.
     */
    IFeeManager public manager;

    /**
     *
     * EVENTS
     *
     */
    event RaffleInitialized();
    event EntriesBought(address indexed user, uint256 entriesBought, uint256 value);
    event EntriesRefunded(address indexed user, uint256 entriesRefunded, uint256 value);
    event PrizesRefunded();
    event DrawSuccess(uint256 indexed requestId, uint256 winnerEntry, address user, uint256 entries);
    event DeadlineSuccessCriteria(uint256 indexed requestId, uint256 entries, uint256 minEntries);
    event DeadlineFailedCriteria(uint256 entries, uint256 minEntries);
    event TokenGatingChanges();

    /**
     *
     * MODIFIERS
     *
     */
    modifier onlyFactory() {
        if (msg.sender != factory) revert RafflErrors.OnlyFactoryAllowed();
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

    // @inheritdoc IRaffl
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

    // @inheritdoc IRaffl
    function criteriaMet() external view override returns (bool) {
        return entries >= minEntries;
    }

    // @inheritdoc IRaffl
    function deadlineExpired() external view override returns (bool) {
        return block.timestamp >= deadline;
    }

    // @inheritdoc IRaffl
    function upkeepPerformed() external view override returns (bool) {
        return settled;
    }

    // @inheritdoc IFeeManager
    function feeData() public view returns (IFeeManager.FeeData memory) {
        return manager.feeData();
    }

    // @inheritdoc IRaffl
    function buyEntries(uint256 quantity) external payable override nonReentrant {
        if (block.timestamp > deadline) revert RafflErrors.EntriesPurchaseClosed();
        _ensureTokenGating(msg.sender);
        if (entryPrice > 0) {
            _purchaseEntry(quantity);
        } else {
            _purchaseFreeEntry();
        }
    }

    // @inheritdoc IRaffl
    function refundEntries(address user) external override nonReentrant {
        if (gameStatus != GameStatus.FailedDraw) revert RafflErrors.RefundsOnlyAllowedOnFailedDraw();
        if (userEntriesMap[user] == 0) revert RafflErrors.UserWithoutEntries();
        if (entryPrice == 0) revert RafflErrors.WithoutRefunds();
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

    // @inheritdoc IRaffl
    function refundPrizes() external payable override nonReentrant {
        if (gameStatus != GameStatus.FailedDraw) revert RafflErrors.RefundsOnlyAllowedOnFailedDraw();
        if (creator != msg.sender) revert RafflErrors.OnlyCreatorAllowed();
        if (prizesRefunded) revert RafflErrors.PrizesAlreadyRefunded();

        // Get feeData once to reduce SLOAD
        IFeeManager.FeeData memory _feeData = feeData();
        if (msg.value != _feeData.feePenality) revert RafflErrors.RefundPenalityRequired();
        if (_feeData.feePenality > 0) {
            payable(_feeData.feeCollector).transfer(_feeData.feePenality);
        }

        prizesRefunded = true;
        _transferPrizes(creator);
        emit PrizesRefunded();
    }

    /**
     *
     * HELPERS
     *
     */

    /**
     * @dev Transfers the prizes to the specified user.
     * @param user The address of the user who will receive the prizes.
     */
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

    /**
     * @dev Transfers the pool balance to the creator of the raffle, after deducting any fees.
     */
    function _transferPool() private {
        uint256 balance =
            (entryToken != address(0)) ? TokenLib.balanceOf(entryToken, address(this)) : address(this).balance;

        if (balance > 0) {
            // Get feeData once to reduce SLOAD
            IFeeManager.FeeData memory _feeData = feeData();
            uint256 fee = 0;

            // If fee is present, calculate it once and subtract from balance
            if (_feeData.feePercentage != 0) {
                fee = (balance * _feeData.feePercentage) / ONE;
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
                    TokenLib.safeTransfer(entryToken, _feeData.feeCollector, fee);
                }
                if (extraRecipientAmount > 0) {
                    TokenLib.safeTransfer(entryToken, extraRecipient.recipient, extraRecipientAmount);
                }
                if (balance > 0) {
                    TokenLib.safeTransfer(entryToken, creator, balance);
                }
            } else {
                if (fee > 0) {
                    payable(_feeData.feeCollector).transfer(fee);
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

    /**
     * @dev Internal function to handle the purchase of entries with entry price greater than 0.
     * @param quantity The quantity of entries to purchase.
     */
    function _purchaseEntry(uint256 quantity) private {
        if (quantity == 0) revert RafflErrors.EntryQuantityRequired();
        uint256 value = quantity * entryPrice;
        // Check if entryToken is a non-zero address, meaning ERC-20 is used for purchase
        if (entryToken != address(0)) {
            // Transfer the required amount of entryToken from user to contract
            // Assumes that the ERC-20 token follows the ERC-20 standard
            TokenLib.safeTransferFrom(entryToken, msg.sender, address(this), value);
        } else {
            // Check that the correct amount of Ether is sent
            if (msg.value != value) revert RafflErrors.EntriesPurchaseInvalidValue();
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

    /**
     * @dev Internal function to handle the purchase of free entries with entry price equal to 0.
     */
    function _purchaseFreeEntry() private {
        // Allow up to one free entry per user
        if (userEntriesMap[msg.sender] == 1) revert RafflErrors.MaxEntriesReached();
        // Assigns the entry index to the user
        entriesMap[entries] = msg.sender;

        // Increments the total number of acquired entries for the raffle
        ++entries;

        // Increments the total number of acquired entries for the user
        ++userEntriesMap[msg.sender];

        // Emits the `EntriesBought` event with zero `value`
        emit EntriesBought(msg.sender, 1, 0);
    }

    /**
     * @notice Ensures that the user has all the requirements from the `tokenGates` array
     * @param user Address of the user
     */
    function _ensureTokenGating(address user) private view {
        uint256 len = tokenGates.length;
        for (uint256 i = 0; i < len;) {
            address token = tokenGates[i].token;
            uint256 amount = tokenGates[i].amount;

            // Extract the returned balance value
            uint256 balance = TokenLib.balanceOf(token, user);

            // Check if the balance meets the requirement
            if (balance < amount) {
                revert RafflErrors.TokenGateRestriction();
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

    // @inheritdoc IRaffl
    function setSuccessCriteria(uint256 requestId) external override onlyFactory {
        gameStatus = GameStatus.DrawStarted;
        emit DeadlineSuccessCriteria(requestId, entries, minEntries);
        settled = true;
    }

    // @inheritdoc IRaffl
    function setFailedCriteria() external override onlyFactory {
        gameStatus = GameStatus.FailedDraw;
        emit DeadlineFailedCriteria(entries, minEntries);
        settled = true;
    }

    // @inheritdoc IRaffl
    function disperseRewards(uint256 requestId, uint256 randomNumber) external override onlyFactory nonReentrant {
        uint256 winnerEntry = randomNumber % entries;
        address winnerUser = entriesMap[winnerEntry];

        _transferPrizes(winnerUser);
        _transferPool();

        gameStatus = GameStatus.SuccessDraw;

        emit DrawSuccess(requestId, winnerEntry, winnerUser, entries);
    }
}
