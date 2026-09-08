// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

interface ISusuPoolVRFReceiver {
    /// @notice Called by SusuVRFManager when randomness arrives
    /// @param seed A single random word to derive the full payout order on-chain
    function fulfillHandOrder(uint256 seed) external;
}
