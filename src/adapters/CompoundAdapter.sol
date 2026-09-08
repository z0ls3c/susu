// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {IYieldAdapter} from "./IYieldAdapter.sol";

interface ICometLike {
    function supply(address asset, uint256 amount) external;
    function withdraw(address asset, uint256 amount) external;
}

contract CompoundAdapter is IYieldAdapter {
    ICometLike public immutable comet;

    constructor(address _comet) {
        comet = ICometLike(_comet);
    }

    function deposit(address asset, uint256 amount) external override {
        // TODO: approve and supply
    }

    function withdraw(
        address,
        /*asset*/
        uint256,
        /*amount*/
        address /*to*/
    )
        external
        pure
        override
        returns (uint256)
    {
        // TODO: withdraw and transfer to `to`
        return 0;
    }

    function totalAssets(
        address /*asset*/
    )
        external
        pure
        override
        returns (uint256)
    {
        return 0; // TODO
    }
}
