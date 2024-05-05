// SPDX-License-Identifier: None
// Raffl Protocol (last updated v1.0.0) (interfaces/IRaffl.sol)
pragma solidity ^0.8.25;

/// @dev Interface that describes the Prize struct, the GameStatus and initialize function so the `RafflFactory` knows
/// how to initialize the `Raffl`.
/// @title IRaffl
interface IRaffl {
    /// @dev Asset type describe the kind of token behind the prize tok describes how the periods between release
    /// tokens.
    enum AssetType {
        ERC20,
        ERC721
    }

    /// @dev `asset` represents the address of the asset considered as a prize
    /// @dev `assetType` defines the type of asset
    /// @dev `value` represents the value of the prize. If asset is an ERC20, it's the amount. If asset is an ERC721,
    /// it's the tokenId.
    struct Prize {
        address asset;
        AssetType assetType;
        uint256 value;
    }

    /// @dev `token` represents the address of the token gating asset
    /// @dev `amount` represents the minimum value of the token gating
    struct TokenGate {
        address token;
        uint256 amount;
    }

    /// @dev `recipient` represents the address of the extra recipient of the pooled funds
    /// @dev `feePercentage` is the percentage of the pooled funds (after fees) that will be shared to the extra
    /// recipient
    struct ExtraRecipient {
        address recipient;
        uint64 sharePercentage;
    }

    /**
     * @dev GameStatus defines the possible states of the game
     * (0) Initialized: Raffle is initialized and ready to receive entries until the deadline
     * (1) FailedDraw: Raffle deadline was hit by the Chailink Upkeep but minimum entries were not met
     * (2) DrawStarted: Raffle deadline was hit by the Chainlink Upkeep and it's waiting for the Chainlink VRF
     *  with the lucky winner
     * (3) SuccessDraw: Raffle received the provably fair and verifiable random lucky winner and distributed rewards.
     */
    enum GameStatus {
        Initialized,
        FailedDraw,
        DrawStarted,
        SuccessDraw
    }

    /// @notice Emit when a new raffle is initialized.
    event RaffleInitialized();

    /// @notice Emit when a user buys entries.
    /// @param user The address of the user who purchased the entries.
    /// @param entriesBought The number of entries bought.
    /// @param value The value of the entries bought.
    event EntriesBought(address indexed user, uint256 entriesBought, uint256 value);

    /// @notice Emit when a user gets refunded for their entries.
    /// @param user The address of the user who got the refund.
    /// @param entriesRefunded The number of entries refunded.
    /// @param value The value of the entries refunded.
    event EntriesRefunded(address indexed user, uint256 entriesRefunded, uint256 value);

    /// @notice Emit when prizes are refunded.
    event PrizesRefunded();

    /// @notice Emit when a draw is successful.
    /// @param requestId The indexed ID of the draw request.
    /// @param winnerEntry The entry that won the draw.
    /// @param user The address of the winner.
    /// @param entries The entries the winner had.
    event DrawSuccess(uint256 indexed requestId, uint256 winnerEntry, address user, uint256 entries);

    /// @notice Emit when the criteria for deadline success is met.
    /// @param requestId The indexed ID of the deadline request.
    /// @param entries The number of entries at the time of the deadline.
    /// @param minEntries The minimum number of entries required for success.
    event DeadlineSuccessCriteria(uint256 indexed requestId, uint256 entries, uint256 minEntries);

    /// @notice Emit when the criteria for deadline failure is met.
    /// @param entries The number of entries at the time of the deadline.
    /// @param minEntries The minimum number of entries required for success.
    event DeadlineFailedCriteria(uint256 entries, uint256 minEntries);

    /// @notice Emit when changes are made to token-gating parameters.
    event TokenGatingChanges();

    /**
     * @notice Initializes the contract by setting up the raffle variables and the
     * `prices` information.
     *
     * @param entryToken        The address of the ERC-20 token as entry. If address zero, entry is the network token
     * @param entryPrice        The value of each entry for the raffle.
     * @param minEntries        The minimum number of entries to consider make the draw.
     * @param deadline          The block timestamp until the raffle will receive entries
     *                          and that will perform the draw if criteria is met.
     * @param creator           The address of the raffle creator
     * @param prizes            The prizes that will be held by this contract.
     * @param tokenGates        The token gating that will be imposed to users.
     * @param extraRecipient    The extra recipient that will share the rewards (optional).
     */
    function initialize(
        address entryToken,
        uint256 entryPrice,
        uint256 minEntries,
        uint256 deadline,
        address creator,
        Prize[] calldata prizes,
        TokenGate[] calldata tokenGates,
        ExtraRecipient calldata extraRecipient
    )
        external;

    /// @notice Checks if the raffle has met the minimum entries
    function criteriaMet() external view returns (bool);

    /// @notice Checks if the deadline has passed
    function deadlineExpired() external view returns (bool);

    /// @notice Checks if raffle already perfomed the upkeep
    function upkeepPerformed() external view returns (bool);

    /// @notice Sets the criteria as settled, sets the `GameStatus` as `DrawStarted` and emits event
    /// `DeadlineSuccessCriteria`
    /// @dev Access control: `factory` is the only allowed to called this method
    function setSuccessCriteria(uint256 requestId) external;

    /// @notice Sets the criteria as settled, sets the `GameStatus` as `FailedDraw` and emits event
    /// `DeadlineFailedCriteria`
    /// @dev Access control: `factory` is the only allowed to called this method
    function setFailedCriteria() external;

    /**
     * @notice Purchase entries for the raffle.
     * @dev Handles the acquisition of entries for three scenarios:
     * i) Entry is paid with network tokens,
     * ii) Entry is paid with ERC-20 tokens,
     * iii) Entry is free (allows up to 1 entry per user)
     * @param quantity The quantity of entries to purchase.
     *
     * Requirements:
     * - If entry is paid with network tokens, the required amount of network tokens.
     * - If entry is paid with ERC-20, the contract must be approved to spend ERC-20 tokens.
     * - If entry is free, no payment is required.
     *
     * Emits `EntriesBought` event
     */
    function buyEntries(uint256 quantity) external payable;

    /// @notice Refund entries for a specific user.
    /// @dev Invokable when the draw was not made because the min entries were not enought
    /// @dev This method is not available if the `entryPrice` was zero
    /// @param user The address of the user whose entries will be refunded.
    function refundEntries(address user) external;

    /// @notice Refund prizes to the creator.
    /// @dev Invokable when the draw was not made because the min entries were not enought
    function refundPrizes() external payable;

    /// @notice Transfers the `prizes` to the provably fair and verifiable entrant, sets the `GameStatus` as
    /// `SuccessDraw` and emits event `DrawSuccess`
    /// @dev Access control: `factory` is the only allowed to called this method through the Chainlink VRF Coordinator
    function disperseRewards(uint256 requestId, uint256 randomNumber) external;
}
