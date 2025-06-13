// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Script, console} from "forge-std/Script.sol";
import "safe-singleton-deployer-sol/src/SafeSingletonDeployer.sol";
import {RedPacket} from "../../src/RedPacket.sol";

contract UpgradeRedPacket is Script {
    bytes32 private constant EXPECTED_UUID = 0x360894a13ba1a3210667c828492db98dca3e2076cc3735a920a3ca505d382bbc; // EIP-1967 impl slot

    function run() public {
        // Read proxy and owner from environment variables
        address proxy = vm.envAddress("PROXY_ADDRESS");
        address owner = vm.envAddress("OWNER_ADDRESS");

        // Generate a unique salt for deterministic deployment
        bytes32 salt = keccak256(abi.encodePacked("RedPacket", "v1.20", owner));

        // Deploy the new implementation contract
        address newImplementation = SafeSingletonDeployer.broadcastDeploy({
            creationCode: type(RedPacket).creationCode,
            args: "",
            salt: salt
        });

        console.log("New RedPacket implementation deployed at:", newImplementation);

        address oldImpl = getImplementation(proxy);
        console.log("Old implementation:", oldImpl);

        // Upgrade the proxy to the new implementation
        vm.startBroadcast();

        // Optional: call a function after upgrade (empty here)
        bytes memory data = "";
        RedPacket(proxy).upgradeToAndCall(newImplementation, data);

        console.log("Proxy upgraded to new implementation");

        // verify current proxy address
        address currentImpl = getImplementation(proxy);
        require(currentImpl == newImplementation, "Upgrade failed: implementation mismatch");

        console.log("Verified implementation:", currentImpl);

        vm.stopBroadcast();
    }

    function getImplementation(address proxy) internal view returns (address impl) {
        bytes32 slot = EXPECTED_UUID;
        impl = address(uint160(uint256(vm.load(proxy, slot))));
    }
}
