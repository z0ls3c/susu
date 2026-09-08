// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

interface ISusuPool {
    enum PoolState {
        Open,
        Locked,
        Ordered,
        Active,
        Closed
    }

    function join() external;
    function lock() external; // finalize members (if not factory-driven)
    function requestOrder() external; // permissionless poke
    function orderedMembers() external view returns (address[] memory);
    function state() external view returns (PoolState);
}
