// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {PoolConfig} from "./utils/PoolConfig.sol";
import {ISusuVRFManager} from "./interfaces/ISusuVRFManager.sol";
import {IPriceOracle} from "./oracle/IPriceOracle.sol";
import {Errors} from "./utils/Errors.sol";

struct Member {
    uint8 hands; // amount of hands (1+)
    uint16 roundsPaid; // number of rounds fully paid (each round = hands * contribution); upfront covers round 1
    bool joined; // has the user joined the pool?
    bool claimed; // has the user claimed their payout?
    uint256 collateral; // in asset units (simplified; extend to multi-asset later)
}

struct MemberHand {
    uint16 hand; // 1-indexed; hand number
    address member; // member address
}

enum PoolState {
    Open, // members can join
    Locked, // no new members; waiting for rotation
    Ordered, // rotation set; accepting contributions (Allow pre-start swaps)
    Active, // payouts underway
    Closed // all payouts complete
}

/// @title SusuPool – rotation savings based on susu/rotating savings and credit associations
/// @author z0l
/// @notice Core contract for managing a susu pool
/// @dev Implements pool states, member management, contributions, payouts, and collateral
contract SusuPool is ReentrancyGuard, Ownable {
    using SafeERC20 for IERC20;
    using PoolConfig for PoolConfig.CollateralParams;

    PoolState public s_pState; // current pool state
    PoolConfig.HandMode public immutable i_handMode; // single or multi-hand pool
    PoolConfig.CollateralParams public s_collat; // collateral configuration

    mapping(address => Member) public s_members;

    address public immutable i_organizer; // the pool creator/manager
    IERC20 public immutable i_asset; // e.g., USDC
    uint8 public immutable i_poolSize; // total hands in the pool
    uint256 public immutable i_poolAmount; // total amount per round
    uint256 public immutable i_contribution; // per-member contribution per round
    uint32 public immutable i_interval; // weeks and months between rounds

    IPriceOracle public s_oracle; // price feeds for collateral (future)

    address public s_factory; // factory that deployed this pool

    address[] public s_rotation; // payout order (to be VRF-populated externally)
    mapping(address => bool) public s_isMember; // Is a member a pool member based on their address?
    mapping(uint16 => bool) public s_handClaimed; // Has a hand claimed its payout?

    uint16 public s_currentHand = 1; // 1-indexed; current hand number
    uint32 public s_lastPayoutTs; // timestamp of last successful payout
    bool public s_poolReady; // all members joined and rotation set

    address public s_vrfManager; // VRF manager for randomness
    bytes32 public s_orderHash; // hash of the finalized order
    uint256 public s_drawSeed; // VRF seed used to derive order
    bool public s_orderRequested; // VRF order request in flight

    event Joined(address indexed user, uint8 hands, uint256 upfront);
    event Contributed(address indexed user, uint256 amount, uint16 hand);
    event Claimed(address indexed user, uint256 amount, uint16 hand);
    event Locked();
    event OrderRequested(uint256 indexed reqId);
    event OrderFinalized(bytes32 orderHash, uint256 seed);

    modifier onlyOrganizer() {
        _onlyOrganizer();
        _;
    }

    modifier onlyVRF() {
        _onlyVRF();
        _;
    }

    /// @notice Initialize the susu pool with given parameters
    /// @param p Initialization parameters
    /// @dev This constructor initializes the pool with the given parameters and sets up the initial state.
    constructor(PoolConfig.InitParams memory p) Ownable(p.organizer) {
        // --- address validations ---
        if (p.organizer == address(0)) revert Errors.SusuPool__OrganizerZeroAddress();
        if (p.asset == address(0)) revert Errors.SusuPool__AssetZeroAddress();
        if (p.oracle == address(0)) revert Errors.SusuPool__OracleZeroAddress();

        // --- poolsize and interval validations ---
        PoolConfig.validatePoolParams(p.poolSize, p.interval);

        // pool amount must be non-zero
        if (p.poolAmount == 0) revert Errors.SusuPool__PoolAmountZero();

        // normalize first if that function clamps/adjusts anything
        PoolConfig.CollateralParams memory normCollat = PoolConfig.normalizeCollateral(p.collat);

        // if collateral is effectively turned on, oracle must not be zero
        if (normCollat.isCollateralEnabled() && p.oracle == address(0)) {
            revert Errors.SusuPool__CollateralNotEnabledZeroOracle();
        }

        // --- state initialization ---
        i_organizer = p.organizer; // organizer/owner
        i_asset = IERC20(p.asset); // e.g., USDC
        i_poolSize = uint8(p.poolSize); // number of members
        i_poolAmount = p.poolAmount; // total amount per round
        i_contribution = p.poolAmount / uint8(p.poolSize); // per-member contribution
        i_interval = uint32(p.interval); // e.g., 1 week or 1 month
        i_handMode = p.handMode; // single or multi-hand
        s_pState = PoolState.Open; // start open
        s_oracle = IPriceOracle(p.oracle); // price oracle
        s_lastPayoutTs = uint32(block.timestamp); // start counting from deployment
        s_collat = normCollat; // store collateral params

        // Record who deployed the pool (factory)
        s_factory = msg.sender;
    }

    // --- membership ---
    /// @notice Join the susu pool with a specified number of hands
    /// @param hands Number of hands to join with
    /// @dev Users can join the pool when it is in the Open state. The number of hands must be valid based on the pool's hand mode.
    function join(uint8 hands) external nonReentrant {
        if (s_pState != PoolState.Open) revert Errors.SusuPool__PoolStateIsNotOpen(); // Pool must be open to join
        if (hands == 0) revert Errors.SusuPool__NoHandsAssigned(); // must assign at least one hand
        if (hands > i_poolSize) revert Errors.SusuPool__TooManyHands(); // no more than pool size
        if (s_rotation.length + hands > i_poolSize) revert Errors.SusuPool__PoolFull(); // no more than pool size
        if (s_isMember[msg.sender]) revert Errors.SusuPool__AlreadyJoined();

        if (i_handMode == PoolConfig.HandMode.Single) {
            // single-hand pool
            if (hands != 1) revert Errors.SusuPool__SingleHandOnly(); // only one hand allowed
        } else if (i_handMode == PoolConfig.HandMode.Multi) {
            // multi-hand pool
            if (hands < PoolConfig.MIN_MULTI_HANDS) revert Errors.SusuPool__MustHaveAtLeastTwoHands(); // at least 2 hands required
        }

        // --- upfront contribution ---
        uint256 upfront = uint256(i_contribution) * hands; // total upfront contribution
        i_asset.safeTransferFrom(msg.sender, address(this), upfront); // collect upfront

        s_isMember[msg.sender] = true; // mark as member
        s_members[msg.sender].hands = hands; // assign hands
        s_members[msg.sender].roundsPaid = 1; // upfront satisfies round 1 (covers all their hands; hand count is in `upfront` above)
        s_members[msg.sender].joined = true; // mark as joined

        for (uint8 i; i < hands; i++) {
            s_rotation.push(msg.sender);
        } // NOTE: placeholder; in production this should be VRF-shuffled externally

        emit Joined(msg.sender, hands, upfront);

        if (s_rotation.length == i_poolSize) {
            s_poolReady = true;
        }
    }

    /// @notice Lock the pool to prevent new members from joining
    /// @dev This function can only be called by the organizer
    function lock() external onlyOrganizer {
        if (s_pState != PoolState.Open) revert Errors.SusuPool__PoolStateNotOpen();
        if (s_rotation.length != i_poolSize) revert Errors.SusuPool__PoolNotReady(); // or check a members list instead of rotation
        s_pState = PoolState.Locked;
        emit Locked();
    }

    // --- rotation management ---
    /// @notice Set the rotation order for the pool
    /// @param order Array of member addresses in the desired rotation order
    /// @dev This function can only be called by the organizer
    function setRotation(address[] calldata order) external onlyOrganizer {
        if (s_pState != PoolState.Locked) revert Errors.SusuPool__PoolStateNotLocked();
        if (s_poolReady) revert Errors.SusuPool__RotationAlreadySet();
        if (s_orderRequested) revert Errors.SusuPool__OrderAlreadyRequested();
        if (order.length != i_poolSize) revert Errors.SusuPool__BadOrderLength();
        s_rotation = order;
        s_poolReady = true;
        s_orderHash = keccak256(abi.encode(order));
    }

    /// @notice Request a new rotation order from the VRF manager
    function requestOrder() external {
        if (s_pState != PoolState.Locked) revert Errors.SusuPool__PoolStateNotLocked();
        if (s_vrfManager == address(0)) revert Errors.SusuPool__VRFManagerZeroAddress();
        if (s_orderRequested) revert Errors.SusuPool__OrderAlreadyRequested(); // prevent double requests
        // Call manager; it returns a requestId
        uint256 reqId = ISusuVRFManager(s_vrfManager).requestHandOrder(address(this));
        // optionally store a flag to prevent double requests
        s_orderRequested = true;
        s_poolReady = false;
        emit OrderRequested(reqId);
    }

    /// @notice Fulfill the VRF request with a new rotation order
    /// @param seed VRF seed used to derive the order
    /// @dev This function can only be called by the VRF manager
    function fulfillHandOrder(uint256 seed) external onlyVRF {
        if (s_pState != PoolState.Locked) revert Errors.SusuPool__PoolStateNotLocked(); // ensure pool is locked
        if (!s_orderRequested) revert Errors.SusuPool__OrderNotRequested(); // ensure a request was made
        if (s_rotation.length != i_poolSize) revert Errors.SusuPool__BadOrderLength(); // use your members list if you switch

        s_drawSeed = seed; // store seed for debugging/audit

        // In-place Fisher–Yates on a memory copy, then commit
        address[] memory arr = s_rotation;
        uint256 n = arr.length;
        for (uint256 i = n; i > 1; i--) {
            uint256 r = uint256(keccak256(abi.encode(seed, i, address(this))));
            uint256 j = r % i; // 0..i-1
            (arr[i - 1], arr[j]) = (arr[j], arr[i - 1]);
        }
        s_rotation = arr; // write ordered list
        s_orderHash = keccak256(abi.encode(arr));
        s_pState = PoolState.Ordered;
        s_poolReady = true; // now “ready” means “order set”
        emit OrderFinalized(s_orderHash, seed);
    }

    // --- contributions ---
    /// @notice Contribute to the pool for the current hand
    /// @param amount Amount to contribute
    /// @dev This function can only be called when the pool is active or ordered
    function contribute(uint256 amount) external nonReentrant {
        if (s_pState != PoolState.Active && s_pState != PoolState.Ordered) {
            revert Errors.SusuPool__PoolStateNotActiveAndOrdered();
        }
        uint8 hands = s_members[msg.sender].hands;
        if (hands == 0) revert Errors.SusuPool__NoHandsAssigned();
        if (!s_isMember[msg.sender]) revert Errors.SusuPool__NotMember();
        if (!s_poolReady) revert Errors.SusuPool__PoolNotReady();
        if (amount != i_contribution * hands) revert Errors.SusuPool__WrongAmount();

        i_asset.safeTransferFrom(msg.sender, address(this), amount);
        s_members[msg.sender].roundsPaid += 1; // one round satisfied; `amount == i_contribution * hands` above already enforces all hands paid

        emit Contributed(msg.sender, amount, s_currentHand);
    }

    // --- start ---
    /// @notice Start the pool after the rotation order is set
    /// @dev This function can only be called by the organizer
    function start() external onlyOrganizer {
        if (s_pState != PoolState.Ordered) revert Errors.SusuPool__PoolNotOrdered();
        // Ensure everyone meets their requirement at their *first upcoming* occurrence
        for (uint256 i = 0; i < s_rotation.length; i++) {
            address u = s_rotation[i];
            uint256 req = _requiredCollateralForTurn(u, i + 1);
            if (s_members[u].collateral < req) revert Errors.SusuPool__UnderCollateralized();
        }
        s_pState = PoolState.Active;
        s_lastPayoutTs = uint32(block.timestamp);
    }

    // --- payout ---
    /// @notice Check if a user is eligible for the current hand
    /// @param user Member address
    /// @param hand Hand number (1-indexed)
    /// @return bool True if eligible, false otherwise
    function isEligibleForHand(address user, uint16 hand) public view returns (bool) {
        if (!s_members[user].joined) return false;
        uint256 req = _requiredCollateralForTurn(user, hand);
        return s_members[user].collateral >= req;
    }

    /// @notice Claim the payout for the current hand
    /// @dev This function can only be called when the pool is active
    function claim() external nonReentrant {
        if (s_pState != PoolState.Active) revert Errors.SusuPool__PoolStateNotActive();
        if (!s_poolReady) revert Errors.SusuPool__PoolNotReady();

        uint16 hand = s_currentHand;

        if (hand == 0 || hand > i_poolSize) revert Errors.SusuPool__InvalidHand();
        if (s_rotation[hand - 1] != msg.sender) revert Errors.SusuPool__NotYourTurn();
        if (s_handClaimed[hand]) revert Errors.SusuPool__AlreadyClaimedHand();
        if (!isEligibleForHand(msg.sender, hand)) revert Errors.SusuPool__NotEligible();
        if (block.timestamp < s_lastPayoutTs + i_interval) revert Errors.SusuPool__WaitInterval();

        uint256 pot = _availablePot();
        // MVP: pay full pot to claimant
        i_asset.safeTransfer(msg.sender, pot);

        s_handClaimed[hand] = true;

        emit Claimed(msg.sender, pot, s_currentHand);

        s_currentHand += 1;
        s_lastPayoutTs = uint32(block.timestamp);

        if (s_currentHand > i_poolSize) {
            s_pState = PoolState.Closed;
        }
    }

    // --- admin helpers ---

    /// @notice Post collateral for the pool
    /// @param amount Amount to post
    /// @dev This function can only be called by a pool member
    function postCollateral(uint256 amount) external nonReentrant {
        if (!s_isMember[msg.sender]) revert Errors.SusuPool__NotMember();
        i_asset.safeTransferFrom(msg.sender, address(this), amount);
        s_members[msg.sender].collateral += amount;
    }

    // --- view ---

    /// @notice Get the round number in which a member is scheduled to receive payout
    /// @param user Member address
    /// @dev Rounds are 1-indexed
    function getMemberHand(address user) external view returns (uint256) {
        if (!s_isMember[user]) revert Errors.SusuPool__NotMember();
        // add 1 because rounds are 1-indexed (currentRound starts at 1)
        return _indexOf(user) + 1;
    }

    /// @notice Get the scheduled round number for each member in the rotation
    /// @return list Array of MemberHand structs
    function getAllMemberHands() external view returns (MemberHand[] memory list) {
        uint256 len = s_rotation.length;
        list = new MemberHand[](len);
        for (uint256 i; i < len; i++) {
            // hand index is 1..i_poolSize, and poolSize is bounded by type(uint16).max in the constructor
            // forge-lint: disable-next-line(unsafe-typecast)
            list[i] = MemberHand({member: s_rotation[i], hand: uint16(i + 1)});
        }
    }

    /// @notice Returns the expected payout amount for the next claimant
    /// @dev This checks actual funds held, so if some contributions are missing, it shows less
    function getNextPayoutAmount() external view returns (uint256) {
        // Start with what the contract is holding
        return i_asset.balanceOf(address(this));
    }

    /// @notice Returns the total pool amount per round (contribution × handSize)
    function getPoolAmount() external view returns (uint256) {
        return uint256(i_contribution) * uint256(i_poolSize);
    }

    function requiredCollateralView(address user, uint256 k1) external view returns (uint256) {
        return _requiredCollateralForTurn(user, k1);
    }

    /// @notice Set the VRF manager address
    /// @param m Address of the VRF manager
    function setVRFManager(address m) external onlyOrganizer {
        if (m == address(0)) revert Errors.SusuPool__VRFManagerZeroAddress();
        s_vrfManager = m;
    }

    /*//////////////////////////////////////////////////////////////
                        INTERNAL FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /// @notice Calculate the available pot for the current hand
    /// @return uint256 Available pot amount
    function _availablePot() internal view returns (uint256) {
        // NOTE: in a real design, you'd track round buckets; MVP uses total balance held in this contract
        return i_asset.balanceOf(address(this));
    }

    /// @notice Find the index of a user in the rotation array
    /// @param user Member address
    /// @return idx Index of the user in the rotation array
    function _indexOf(address user) internal view returns (uint256 idx) {
        for (uint256 i; i < s_rotation.length; i++) {
            if (s_rotation[i] == user) return i;
        }
        revert Errors.SusuPool__UserNotInRotation();
    }

    /// @notice Calculate the required collateral for a member in a specific turn
    /// @param user Member address
    /// @param k1 Turn number (1-indexed)
    /// @return uint256 Required collateral amount
    function _requiredCollateralForTurn(address user, uint256 k1) internal view returns (uint256) {
        return PoolConfig.requiredCollateral(s_collat, i_poolSize, i_contribution, s_members[user].hands, k1);
    }

    /// @notice Ensure the caller is the organizer
    /// @dev This function reverts if the caller is not the organizer
    function _onlyOrganizer() internal view {
        if (msg.sender != i_organizer) revert Errors.SusuPool__NotOrganizer();
    }

    /// @notice Ensure the caller is the VRF manager
    /// @dev This function reverts if the caller is not the VRF manager
    function _onlyVRF() internal view {
        if (msg.sender != s_vrfManager) revert Errors.SusuPool__NotVRFManager();
    }
}
