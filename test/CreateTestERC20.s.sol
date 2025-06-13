// script/CreateTestERC20.s.sol
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Script.sol";
import "./TestToken.sol";

contract CreateTestERC20 is Script {
    function run() external {
        vm.startBroadcast();

        // Mint 1,000,000 TST tokens (with 18 decimals)
        TestToken token = new TestToken(1_000_000 ether);

        console.log("TestToken deployed at:", address(token));

        vm.stopBroadcast();
    }
}
