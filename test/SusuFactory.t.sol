// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Test} from "forge-std/Test.sol";
import {SusuFactory} from "../src/SusuFactory.sol";

contract SusuFactoryTest is Test {
    function testCreate() public {
        SusuFactory f = new SusuFactory(address(this));
        // would need a mock ERC20 + mock oracle to fully test
        assertEq(address(f) != address(0), true);
    }
}
