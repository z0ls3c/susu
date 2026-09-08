// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {console2} from "forge-std/console2.sol";
import {Script} from "forge-std/Script.sol";
import {SusuFactory} from "../src/SusuFactory.sol";

contract DeployFactory is Script {
    function run() external {
        uint256 pk = vm.envUint("PRIVATE_KEY");
        vm.startBroadcast(pk);
        SusuFactory factory = new SusuFactory(msg.sender);
        console2.log("SusuFactory:", address(factory));
        vm.stopBroadcast();
    }
}
