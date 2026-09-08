// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {IYieldAdapter} from "./IYieldAdapter.sol";

interface IAavePoolV3 {
    function supply(address asset, uint256 amount, address onBehalfOf, uint16 referralCode) external;
    function withdraw(address asset, uint256 amount, address to) external returns (uint256);
}

contract AaveAdapter is IYieldAdapter {
    using SafeERC20 for IERC20;

    IAavePoolV3 public immutable pool;

    constructor(address _pool) {
        pool = IAavePoolV3(_pool);
    }

    function deposit(address asset, uint256 amount) external override {
        IERC20(asset).safeIncreaseAllowance(address(pool), amount);
        pool.supply(asset, amount, address(this), 0);
    }

    function withdraw(address asset, uint256 amount, address to) external override returns (uint256) {
        return pool.withdraw(asset, amount, to);
    }

    // NOTE: For aave, totalAssets would need to read aToken balance; keep stubby for scaffold
    function totalAssets(
        address /*asset*/
    )
        external
        pure
        override
        returns (uint256)
    {
        return 0; // TODO: wire to aToken balances
    }
}
