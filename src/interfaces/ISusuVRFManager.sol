// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

interface ISusuVRFManager {
    /// @notice Request a new hand order for the given pool
    /// @param pool The address of the SusuPool requesting randomness
    /// @return requestId The VRF request ID
    function requestHandOrder(address pool) external returns (uint256);
}
