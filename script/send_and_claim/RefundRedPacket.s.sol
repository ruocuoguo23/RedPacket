// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Script.sol";
import "../../src/RedPacket.sol";

contract RefundRedPacket is Script {
    function run() external {
        address redPacketAddress = vm.envAddress("REDPACKET_ADDRESS");
        RedPacket redPacket = RedPacket(redPacketAddress);

        string memory rawPacketId = vm.envString("PACKET_ID");
        bytes32 packetId = keccak256(bytes(rawPacketId));

        vm.warp(block.timestamp + 25 hours);

        vm.startBroadcast(vm.envUint("SENDER_PK"));
        redPacket.refundExpiredPackets(packetId);
        vm.stopBroadcast();
    }
}
