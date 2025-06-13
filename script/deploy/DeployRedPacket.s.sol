// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Script, console} from "forge-std/Script.sol";
import "safe-singleton-deployer-sol/src/SafeSingletonDeployer.sol";
import {RedPacket} from "../../src/RedPacket.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";

contract DeployRedPacketScript is Script {
    function run() public {
        // Load from env
        address owner = vm.envAddress("OWNER_ADDRESS"); // Contract owner
        address vrfCoordinator = vm.envAddress("VRF_COORDINATOR");
        bytes32 keyHash = vm.envBytes32("VRF_KEY_HASH");
        uint256 subscriptionId = vm.envUint("VRF_SUBSCRIPTION_ID");
        address signer = vm.envAddress("SIGNER_ADDRESS");
        uint32 callbackGasLimit = 500000;
        uint16 requestConfirmations = 3;

        // Generate a salt to ensure the same contract address across different chains
        bytes32 salt = keccak256(abi.encodePacked("RedPacket", "v1.10", owner));

        // Log the current chain ID
        console.log("chain id", block.chainid);

        // Deploy the RedPacket contract using SafeSingletonDeployer
        address implementation = SafeSingletonDeployer.broadcastDeploy({
            creationCode: type(RedPacket).creationCode,
            args: "",
            salt: salt
        });

        console.log("RedPacket Implementation deployed at", implementation);

        // Step 2: Deploy proxy with initialization
        vm.startBroadcast();

        ERC1967Proxy proxy = new ERC1967Proxy(
            implementation,
            abi.encodeWithSelector(
                RedPacket.initialize.selector,
                vrfCoordinator,
                keyHash,
                subscriptionId,
                callbackGasLimit,
                requestConfirmations,
                signer
            )
        );

        console.log("RedPacket Proxy deployed at", address(proxy));

        vm.stopBroadcast();
    }
}
