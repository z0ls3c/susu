// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

interface ISusuFactory {
    event PoolCreated(address indexed pool, address indexed organizer, address asset, uint256 size);
    function createPool( /* params */ ) external returns (address pool);
    // optionally: function lockPool(address pool) external;
}
