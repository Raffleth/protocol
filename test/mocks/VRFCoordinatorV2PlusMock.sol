// SPDX-License-Identifier: None
pragma solidity ^0.8.27;

import { ConfirmedOwner } from "@chainlink/contracts/src/v0.8/shared/access/ConfirmedOwner.sol";
import { VRFV2PlusClient } from "@chainlink/contracts/src/v0.8/vrf/dev/libraries/VRFV2PlusClient.sol";
import { VRFConsumerBaseV2Plus } from "@chainlink/contracts/src/v0.8/vrf/dev/VRFConsumerBaseV2Plus.sol";
import { IVRFCoordinatorV2Plus } from "@chainlink/contracts/src/v0.8/vrf/dev/interfaces/IVRFCoordinatorV2Plus.sol";

contract VRFCoordinatorV2PlusMock is IVRFCoordinatorV2Plus, ConfirmedOwner {
    uint96 public immutable BASE_FEE;
    uint96 public immutable GAS_PRICE_LINK;
    uint16 public immutable MAX_CONSUMERS = 100;

    error InvalidSubscription();
    error InsufficientBalance();
    error MustBeSubOwner(address owner);
    error TooManyConsumers();
    error InvalidConsumer();
    error InvalidRandomWords();
    error Reentrant();

    event RandomWordsRequested(
        bytes32 indexed keyHash,
        uint256 requestId,
        uint256 preSeed,
        uint256 indexed subId,
        uint16 minimumRequestConfirmations,
        uint32 callbackGasLimit,
        uint32 numWords,
        bytes extraArgs,
        address indexed sender
    );

    event RandomWordsFulfilled(uint256 indexed requestId, uint256 outputSeed, uint96 payment, bool success);
    event SubscriptionCreated(uint256 indexed subId, address owner);
    event SubscriptionFunded(uint256 indexed subId, uint256 oldBalance, uint256 newBalance);
    event SubscriptionCanceled(uint256 indexed subId, address to, uint256 amount);
    event ConsumerAdded(uint256 indexed subId, address consumer);
    event ConsumerRemoved(uint256 indexed subId, address consumer);
    event ConfigSet();

    struct Config {
        // Reentrancy protection.
        bool reentrancyLock;
    }

    Config private s_config;
    uint256 internal s_currentSubId;
    uint256 internal s_nextRequestId = 1;
    uint256 internal s_nextPreSeed = 100;

    struct Subscription {
        address owner;
        uint96 balance;
    }

    mapping(uint256 => Subscription) internal s_subscriptions; /* subId */ /* subscription */
    mapping(uint256 => address[]) internal s_consumers; /* subId */ /* consumers */

    struct Request {
        uint256 subId;
        uint32 callbackGasLimit;
        uint32 numWords;
    }

    mapping(uint256 => Request) internal s_requests; /* requestId */ /* request */

    constructor(uint96 _baseFee, uint96 _gasPriceLink) ConfirmedOwner(msg.sender) {
        BASE_FEE = _baseFee;
        GAS_PRICE_LINK = _gasPriceLink;
        setConfig();
    }

    /**
     * @notice Sets the configuration of the vrfv2 mock coordinator
     */
    function setConfig() public onlyOwner {
        s_config = Config({ reentrancyLock: false });
        emit ConfigSet();
    }

    function consumerIsAdded(uint256 _subId, address _consumer) public view returns (bool) {
        address[] memory consumers = s_consumers[_subId];
        for (uint256 i = 0; i < consumers.length; i++) {
            if (consumers[i] == _consumer) {
                return true;
            }
        }
        return false;
    }

    modifier onlyValidConsumer(uint256 _subId, address _consumer) {
        if (!consumerIsAdded(_subId, _consumer)) {
            revert InvalidConsumer();
        }
        _;
    }

    /**
     * @notice fulfillRandomWords fulfills the given request, sending the random words to the supplied
     * @notice consumer.
     *
     * @dev This mock uses a simplified formula for calculating payment amount and gas usage, and does
     * @dev not account for all edge cases handled in the real VRF coordinator. When making requests
     * @dev against the real coordinator a small amount of additional LINK is required.
     *
     * @param _requestId the request to fulfill
     * @param _consumer the VRF randomness consumer to send the result to
     */
    function fulfillRandomWords(uint256 _requestId, address _consumer) external nonReentrant {
        fulfillRandomWordsWithOverride(_requestId, _consumer, new uint256[](0));
    }

    /**
     * @notice fulfillRandomWordsWithOverride allows the user to pass in their own random words.
     *
     * @param _requestId the request to fulfill
     * @param _consumer the VRF randomness consumer to send the result to
     * @param _words user-provided random words
     */
    function fulfillRandomWordsWithOverride(uint256 _requestId, address _consumer, uint256[] memory _words) public {
        uint256 startGas = gasleft();
        if (s_requests[_requestId].subId == 0) {
            revert("nonexistent request");
        }
        Request memory req = s_requests[_requestId];

        if (_words.length == 0) {
            _words = new uint256[](req.numWords);
            for (uint256 i = 0; i < req.numWords; i++) {
                _words[i] = uint256(keccak256(abi.encode(_requestId, i)));
            }
        } else if (_words.length != req.numWords) {
            revert InvalidRandomWords();
        }

        VRFConsumerBaseV2Plus v;
        bytes memory callReq = abi.encodeWithSelector(v.rawFulfillRandomWords.selector, _requestId, _words);
        s_config.reentrancyLock = true;
        (bool success,) = _consumer.call{ gas: req.callbackGasLimit }(callReq);
        s_config.reentrancyLock = false;

        uint96 payment = uint96(BASE_FEE + ((startGas - gasleft()) * GAS_PRICE_LINK));
        if (s_subscriptions[req.subId].balance < payment) {
            revert InsufficientBalance();
        }
        s_subscriptions[req.subId].balance -= payment;
        delete (s_requests[_requestId]);
        emit RandomWordsFulfilled(_requestId, _requestId, payment, success);
    }

    /**
     * @notice fundSubscription allows funding a subscription with an arbitrary amount for testing.
     *
     * @param _subId the subscription to fund
     * @param _amount the amount to fund
     */
    function fundSubscription(uint256 _subId, uint96 _amount) public {
        if (s_subscriptions[_subId].owner == address(0)) {
            revert InvalidSubscription();
        }
        uint96 oldBalance = s_subscriptions[_subId].balance;
        s_subscriptions[_subId].balance += _amount;
        emit SubscriptionFunded(_subId, oldBalance, oldBalance + _amount);
    }

    function requestRandomWords(VRFV2PlusClient.RandomWordsRequest calldata req)
        external
        override
        nonReentrant
        returns (uint256 requestId)
    {
        uint256 subId = req.subId;
        if (s_subscriptions[subId].owner == address(0)) {
            revert InvalidSubscription();
        }

        requestId = s_nextRequestId++;
        uint256 preSeed = s_nextPreSeed++;

        s_requests[requestId] =
            Request({ subId: subId, callbackGasLimit: req.callbackGasLimit, numWords: req.numWords });

        emit RandomWordsRequested(
            req.keyHash,
            requestId,
            preSeed,
            subId,
            req.requestConfirmations,
            req.callbackGasLimit,
            req.numWords,
            req.extraArgs,
            msg.sender
        );

        return requestId;
    }

    function createSubscription() external override returns (uint256 _subId) {
        s_currentSubId++;
        s_subscriptions[s_currentSubId] = Subscription({ owner: msg.sender, balance: 0 });
        emit SubscriptionCreated(s_currentSubId, msg.sender);
        return s_currentSubId;
    }

    function getSubscription(uint256 _subId)
        external
        view
        returns (uint96 balance, uint96 nativeBalance, uint64 reqCount, address owner, address[] memory consumers)
    {
        if (s_subscriptions[_subId].owner == address(0)) {
            revert InvalidSubscription();
        }
        return (s_subscriptions[_subId].balance, 0, 0, s_subscriptions[_subId].owner, s_consumers[_subId]);
    }

    function cancelSubscription(uint256 _subId, address _to) external onlySubOwner(_subId) nonReentrant {
        emit SubscriptionCanceled(_subId, _to, s_subscriptions[_subId].balance);
        delete (s_subscriptions[_subId]);
    }

    modifier onlySubOwner(uint256 _subId) {
        address owner = s_subscriptions[_subId].owner;
        if (owner == address(0)) {
            revert InvalidSubscription();
        }
        if (msg.sender != owner) {
            revert MustBeSubOwner(owner);
        }
        _;
    }

    function addConsumer(uint256 _subId, address _consumer) external onlySubOwner(_subId) {
        if (s_consumers[_subId].length == MAX_CONSUMERS) {
            revert TooManyConsumers();
        }

        if (consumerIsAdded(_subId, _consumer)) {
            return;
        }

        s_consumers[_subId].push(_consumer);
        emit ConsumerAdded(_subId, _consumer);
    }

    function removeConsumer(
        uint256 _subId,
        address _consumer
    )
        external
        onlySubOwner(_subId)
        onlyValidConsumer(_subId, _consumer)
        nonReentrant
    {
        address[] storage consumers = s_consumers[_subId];
        for (uint256 i = 0; i < consumers.length; i++) {
            if (consumers[i] == _consumer) {
                address last = consumers[consumers.length - 1];
                consumers[i] = last;
                consumers.pop();
                break;
            }
        }

        emit ConsumerRemoved(_subId, _consumer);
    }

    modifier nonReentrant() {
        if (s_config.reentrancyLock) {
            revert Reentrant();
        }
        _;
    }

    function requestSubscriptionOwnerTransfer(uint256, /*_subId*/ address /*_newOwner*/ ) external pure override {
        revert("not implemented");
    }

    function acceptSubscriptionOwnerTransfer(uint256 /*_subId*/ ) external pure override {
        revert("not implemented");
    }

    function pendingRequestExists(uint256 /*subId*/ ) public pure override returns (bool) {
        revert("not implemented");
    }

    function getActiveSubscriptionIds(
        uint256, /*startIndex*/
        uint256 /*maxCount*/
    )
        external
        pure
        override
        returns (uint256[] memory)
    {
        revert("not implemented");
    }

    function fundSubscriptionWithNative(uint256 /*subId*/ ) external payable override {
        revert("not implemented");
    }

    /// @dev Exposing only for Testing purposes
    function nextRequestId() external view returns (uint256) {
        return s_nextRequestId;
    }
}
