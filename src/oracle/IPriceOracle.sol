// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

interface IPriceOracle {
    /// @notice returns price in 1e8 decimals (like Chainlink)
    function latestAnswer(address asset) external view returns (int256);
    function decimals(address asset) external view returns (uint8);
}
