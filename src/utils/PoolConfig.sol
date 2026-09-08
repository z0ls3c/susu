// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Errors} from "./Errors.sol";

library PoolConfig {
    enum HandMode {
        Single, // one hand per member
        Multi // members can have multiple hands (up to poolSize)
    }

    // ----------- initialization -----------
    struct InitParams {
        address organizer; // the pool creator/manager
        address asset; // ERC20 used for contributions/bonds
        uint8 poolSize; // number of members
        uint32 interval; // time between rounds
        uint256 poolAmount; // total contribution amount per round
        address oracle; // price oracle
        HandMode handMode; // hand mode (single/multiple)
        PoolConfig.CollateralParams collat; // collateral parameters
    }

    // ---------- Collateral policy ----------
    struct CollateralParams {
        uint8 waiveAfterK; // waive requirement for last K turns (0 = never)
        uint16 ratioBps; // base % of unpaid future dues (1e4 = 100%)
        uint16 slopeBps; // extra weight for earlier turns (0..10000)
        uint256 minCollateral; // absolute floor
        uint256 maxCollateral; // cap (0 = no cap)
    }

    // pool rules (single source of truth)
    uint8 internal constant MIN_MULTI_HANDS = 2;
    uint8 internal constant MIN_POOL_SIZE = 5;
    uint8 internal constant MAX_POOL_SIZE = 25;
    uint16 internal constant DEFAULT_RATIO_BPS = 10_000; // 100%
    uint32 internal constant MIN_INTERVAL = 7 days;
    uint32 internal constant MAX_INTERVAL = 30 days;

    /// @notice Validate basic config invariants for pool creation
    /// @param poolSize Number of members in the pool
    /// @param interval Time between rounds in seconds
    /// @dev Reverts if any parameter is out of bounds
    function validatePoolParams(uint8 poolSize, uint32 interval) internal pure {
        if (poolSize < MIN_POOL_SIZE) revert Errors.PoolConfig__PoolSizeTooSmall();
        if (poolSize > MAX_POOL_SIZE) revert Errors.PoolConfig__PoolSizeTooBig();
        if (interval != MIN_INTERVAL && interval != MAX_INTERVAL) revert Errors.PoolConfig__InvalidInterval();
    }

    /// @notice Apply defaults / normalization to collateral params
    /// @param c CollateralParams struct to normalize
    /// @return normalized CollateralParams with defaults applied
    /// @dev If ratioBps is zero, sets it to DEFAULT_RATIO_BPS (100%)
    function normalizeCollateral(CollateralParams memory c) internal pure returns (CollateralParams memory) {
        // Default: if ratio is not set, require 100% of unpaid future dues
        if (c.ratioBps == 0) {
            c.ratioBps = DEFAULT_RATIO_BPS;
        }
        // you could clamp here if you want strict bounds, e.g.:
        // if (c.ratioBps > 10_000) revert Errors.COLLATERAL_RATIO_TOO_HIGH();
        // if (c.slopeBps > 10_000) revert Errors.COLLATERAL_SLOPE_TOO_HIGH();
        return c;
    }

    /// @notice Core collateral math: how much collateral is required for this hand
    /// @param c    Collateral config
    /// @param N    Pool size (number of hands / rounds)
    /// @param C    Per-hand contribution amount
    /// @param hands Number of hands the user has
    /// @param k1   1-indexed turn of this hand (1..N)
    /// @return req  Required collateral amount
    /// @dev Uses linear weighting based on slopeBps; respects min/max collateral
    function requiredCollateral(CollateralParams memory c, uint256 N, uint256 C, uint8 hands, uint256 k1)
        internal
        pure
        returns (uint256 req)
    {
        if (N == 0 || hands == 0) return 0;
        if (k1 == 0 || k1 > N) revert Errors.PoolConfig__InvalidTurn();

        if (c.waiveAfterK >= N) return 0;
        if (c.waiveAfterK != 0 && k1 > (N - c.waiveAfterK)) return 0;

        uint256 remainingRounds = N - k1;
        uint256 unpaidDues = remainingRounds * C * hands;

        // Weight increases for earlier turns if slopeBps > 0
        uint256 weightBps = uint256(c.ratioBps) + (uint256(c.slopeBps) * (N - k1)) / N; // safe since N>0

        req = (unpaidDues * weightBps) / DEFAULT_RATIO_BPS;

        if (req < c.minCollateral) req = c.minCollateral;
        if (c.maxCollateral != 0 && req > c.maxCollateral) {
            req = c.maxCollateral;
        }
    }

    // Optional: expose read-only getters so frontends can use them via any contract
    function minPoolSize() internal pure returns (uint8) {
        return MIN_POOL_SIZE;
    }

    function maxPoolSize() internal pure returns (uint8) {
        return MAX_POOL_SIZE;
    }

    function minInterval() internal pure returns (uint32) {
        return MIN_INTERVAL;
    }

    function maxInterval() internal pure returns (uint32) {
        return MAX_INTERVAL;
    }

    function isCollateralEnabled(CollateralParams memory c) internal pure returns (bool) {
        return c.ratioBps > 0 || c.minCollateral > 0 || c.maxCollateral > 0 || c.slopeBps > 0 || c.waiveAfterK > 0;
    }
}
