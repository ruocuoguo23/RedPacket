// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Script.sol";
import {RedPacket} from "../../src/RedPacket.sol";

contract UpdateSigner is Script {
    function run() external {
        address redPacketAddress = vm.envAddress("REDPACKET_ADDRESS");
        address newSigner = vm.envAddress("NEW_SIGNER");

        vm.startBroadcast();

        RedPacket(redPacketAddress).updateSigner(newSigner);

        vm.stopBroadcast();
    }
}
