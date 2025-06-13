// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Script.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

contract SendToken is Script {
    function run() external {
        address tokenAddress = vm.envAddress("TOKEN_ADDRESS");
        address targetAddress = vm.envAddress("TARGET_ADDRESS");

        uint256 amount = 100 ether;

        IERC20 token = IERC20(tokenAddress);

        vm.startBroadcast();
        token.transfer(targetAddress, amount);
        vm.stopBroadcast();
    }
}
