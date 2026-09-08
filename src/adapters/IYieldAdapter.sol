// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

interface IYieldAdapter {
    function deposit(address asset, uint256 amount) external;
    function withdraw(address asset, uint256 amount, address to) external returns (uint256);
    function totalAssets(address asset) external view returns (uint256);
}
