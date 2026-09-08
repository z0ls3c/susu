// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {VRFConsumerBaseV2Plus} from "@chainlink/contracts/src/v0.8/vrf/dev/VRFConsumerBaseV2Plus.sol";
import {VRFV2PlusClient} from "@chainlink/contracts/src/v0.8/vrf/dev/libraries/VRFV2PlusClient.sol";
import {ISusuPoolVRFReceiver} from "../interfaces/ISusuPoolVRFReceiver.sol";
import {Errors} from "../utils/Errors.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

contract SusuVRFManager is VRFConsumerBaseV2Plus, ReentrancyGuard {
    // ---- VRF config ----
    uint256 public immutable i_subscriptionId; // Chainlink VRF subscription ID
    bytes32 public immutable i_keyHash; // aka gas lane (chain-specific)

    uint32 public s_callbackGasLimit; // tune based on your pool size & shuffle cost
    uint16 public s_requestConfirmations; // security vs latency tradeoff
    uint32 public s_numWords; // single seed, derive rest on-chain
    bool public s_payWithNative; // false = LINK, true = native

    // requestId -> pool that asked for randomness
    mapping(uint256 => address) private s_requestToPool;

    address public s_factory;

    event FactorySet(address indexed factory);
    event HandOrderRequested(uint256 indexed requestId, address indexed pool);
    event HandOrderFulfilled(uint256 indexed requestId, address indexed pool, uint256 seed);

    event ParamsUpdated(uint32 gasLimit, uint16 confs, uint32 words, bool payNative);

    modifier onlyFactory() {
        _onlyFactory();
        _;
    }

    constructor(
        uint256 subscriptionId,
        address vrfCoordinator,
        bytes32 keyHash,
        address factory,
        uint32 callbackGasLimit, // e.g., 300_000
        uint16 requestConfirmations, // e.g., 3
        uint32 numWords, // e.g., 1
        bool payWithNative // false = pay LINK, true = pay native
    ) VRFConsumerBaseV2Plus(vrfCoordinator) {
        if(factory == address(0)) revert Errors.SusuVRFManager__ZeroAddress();
        if(vrfCoordinator == address(0)) revert Errors.SusuVRFManager__ZeroAddress();

        i_subscriptionId = subscriptionId;
        i_keyHash = keyHash;
        s_factory = factory;
        s_callbackGasLimit = callbackGasLimit == 0 ? 300_000 : callbackGasLimit;
        s_requestConfirmations = requestConfirmations == 0 ? 3 : requestConfirmations;
        s_numWords = numWords == 0 ? 1 : numWords;
        s_payWithNative = payWithNative;

        emit FactorySet(factory);
        emit ParamsUpdated(s_callbackGasLimit, s_requestConfirmations, s_numWords, s_payWithNative);
    }

    // Owner can adjust knobs post-deploy if profiling dictates
    function setParams(uint32 gasLimit, uint16 confs, uint32 words, bool payNative) external onlyOwner {
        s_callbackGasLimit = gasLimit == 0 ? s_callbackGasLimit : gasLimit;
        s_requestConfirmations = confs == 0 ? s_requestConfirmations : confs;
        s_numWords = words == 0 ? s_numWords : words;
        s_payWithNative = payNative;
        emit ParamsUpdated(s_callbackGasLimit, s_requestConfirmations, s_numWords, s_payWithNative);
    }

    function setFactory(address factory) external onlyOwner {
        if(factory == address(0)) revert Errors.SusuVRFManager__ZeroAddress();
        s_factory = factory;
        emit FactorySet(factory);
    }

    function setCallbackGasLimit(uint32 g) external onlyOwner {
        s_callbackGasLimit = g;
    }

    function setConfirmations(uint16 confs) external onlyOwner {
        s_requestConfirmations = confs;
    }

    // Called by SusuFactory / pools (via factory) once a pool is locked
    function requestHandOrder(address pool) external onlyFactory returns (uint256 reqId) {
        if (pool == address(0)) revert Errors.SusuVRFManager__ZeroAddress();
        reqId = s_vrfCoordinator.requestRandomWords(
            VRFV2PlusClient.RandomWordsRequest({
                keyHash: i_keyHash,
                subId: i_subscriptionId,
                requestConfirmations: s_requestConfirmations,
                callbackGasLimit: s_callbackGasLimit,
                numWords: s_numWords,
                // Pay with LINK by default; set true to pay with native token if your sub is funded that way
                extraArgs: VRFV2PlusClient._argsToBytes(VRFV2PlusClient.ExtraArgsV1({nativePayment: s_payWithNative}))
            })
        );
        s_requestToPool[reqId] = pool;
        emit HandOrderRequested(reqId, pool);
    }

    // VRF callback
    function fulfillRandomWords(uint256 requestId, uint256[] calldata randomWords) internal override {
        address pool = s_requestToPool[requestId];
        if(pool == address(0)) revert Errors.SusuVRFManager__ZeroAddress();
        uint256 seed = randomWords[0];
        delete s_requestToPool[requestId];
        ISusuPoolVRFReceiver(pool).fulfillHandOrder(seed);
        emit HandOrderFulfilled(requestId, pool, seed);
    }

    function getCoordinator() external view returns (address) {
        return address(s_vrfCoordinator); // from the Chainlink base
    }

    function _onlyFactory() internal view {
        if (msg.sender != s_factory) revert Errors.SusuVRFManager__NotFactory();
    }
}
