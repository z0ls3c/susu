// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Script} from "forge-std/Script.sol";
import {console2} from "forge-std/console2.sol";
import {SusuFactory} from "../src/SusuFactory.sol";
import {PoolConfig} from "../src/utils/PoolConfig.sol";

contract CreatePool is Script {
    function run() external {
        uint256 pk = vm.envUint("PRIVATE_KEY");
        address factoryAddr = vm.envAddress("FACTORY_ADDR");
        address asset = vm.envAddress("ASSET"); // e.g. USDC
        address oracle = vm.envAddress("ORACLE");

        // --- Pool configuration from env vars ---
        uint8 poolSize = uint8(vm.envUint("POOL_SIZE"));
        uint32 interval = uint32(vm.envUint("POOL_INTERVAL")); // in seconds
        uint256 poolAmt = vm.envUint("POOL_AMOUNT"); // e.g. 5000e6 for USDC

        // Hand mode (0 = Single, 1 = Multi)
        uint256 handModeRaw = vm.envOr("HAND_MODE", uint256(0));
        PoolConfig.HandMode mode = handModeRaw == 0 ? PoolConfig.HandMode.Single : PoolConfig.HandMode.Multi;

        vm.startBroadcast(pk);

        SusuFactory factory = SusuFactory(factoryAddr);
        address pool = factory.createPool(
            SusuFactory.PoolParams({
                asset: asset,
                poolSize: poolSize,
                interval: interval,
                poolAmount: poolAmt,
                oracle: oracle,
                handMode: mode
            })
        );

        console2.log("SusuPool deployed at:", pool);

        vm.stopBroadcast();
    }
}
