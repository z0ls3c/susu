// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {AccessControl} from "@openzeppelin/contracts/access/AccessControl.sol";
import {EnumerableSet} from "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";
import {SusuPool} from "./SusuPool.sol";
import {PoolConfig} from "./utils/PoolConfig.sol";
import {Errors} from "./utils/Errors.sol";

/// @title SusuFactory - Factory contract for creating Susu pools
/// @author z0l
/// @notice Factory contract to create and manage Susu pools
/// @dev Uses AccessControl for role-based permissions
/// @dev Uses EnumerableSet to track all created pools
contract SusuFactory is AccessControl {
    using EnumerableSet for EnumerableSet.AddressSet; // this is for managing the set of all pools

    struct PoolParams {
        address asset; // ERC20 used for contributions/bonds
        uint8 poolSize; // number of members
        uint32 interval; // seconds between rounds
        uint256 poolAmount; // per-interval contribution amount
        address oracle; // price oracle
        PoolConfig.HandMode handMode; // hand mode (single/multiple)
    }

    bytes32 public constant ORGANIZER_ROLE = keccak256("ORGANIZER_ROLE"); // The role allowed to create pools

    EnumerableSet.AddressSet private s_allPools; // set of all pools created

    event PoolCreated(address indexed pool, address indexed organizer, address asset, uint8 poolSize); // emitted when a new pool is created

    constructor(address admin) {
        // admin is the deployer/owner
        _grantRole(DEFAULT_ADMIN_ROLE, admin); // admin gets default admin role
        _grantRole(ORGANIZER_ROLE, admin); // admin gets organizer role
    }

    /*//////////////////////////////////////////////////////////////
                        POOL CREATION LOGIC
    //////////////////////////////////////////////////////////////*/
    
    /// @notice Create a new Susu pool with specified parameters
    /// @dev Caller must have ORGANIZER_ROLE
    /// @param p PoolParams struct containing pool configuration
    /// @return address of the newly created Susu pool
        function createPool(PoolParams memory p) external onlyRole(ORGANIZER_ROLE) returns (address) {
        // sanity checks up front
        PoolConfig.validatePoolParams(p.poolSize, p.interval);

        // bond can be zero (optional)
        if(p.asset == address(0)) revert Errors.SusuFactory__InvalidAsset(); // asset must be valid address
        if(p.oracle == address(0)) revert Errors.SusuFactory__InvalidOracle(); // oracle must be valid address
        SusuPool pool = new SusuPool( // pool deployment
            PoolConfig.InitParams({ // initialize the pool with these parameters below
                organizer: msg.sender, // the creator of the pool
                asset: p.asset, // asset for contributions/bonds
                poolSize: uint8(p.poolSize), // number of members
                interval: uint32(p.interval), // interval between rounds
                poolAmount: p.poolAmount, // total pool amount per round
                oracle: p.oracle, // price oracle
                handMode: p.handMode, // hand mode (single/multiple)
                collat: // collateral configuration
                PoolConfig.CollateralParams({
                    ratioBps: 0, // no collateral
                    slopeBps: 0, // no slope
                    waiveAfterK: 0, // no waiver
                    minCollateral: 0, // no minimum
                    maxCollateral: 0 // no maximum
                })
            })
        );
        s_allPools.add(address(pool)); // pool added to state
        emit PoolCreated(address(pool), msg.sender, p.asset, p.poolSize);
        return address(pool); // return the address of the newly created pool
    }

    /*//////////////////////////////////////////////////////////////
                        EXTERNAL FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /// @notice Get the number of pools created
    /// @return number of pools
    /// @dev returns the length of the set of all pools
    function getNumOfPools() external view returns (uint256) {
        return s_allPools.length();
    }

    /// @notice Get the addresses of all pools created
    /// @return arr array of pool addresses
    /// @dev returns an array of all pool addresses
    function getAllPoolAddresses() external view returns (address[] memory arr) {
        arr = new address[](s_allPools.length());
        for (uint256 i; i < arr.length; i++) {
            arr[i] = s_allPools.at(i);
        }
    }
}
