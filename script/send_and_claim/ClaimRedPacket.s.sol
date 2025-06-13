// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Script.sol";
import "../../src/RedPacket.sol";
import "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import "@openzeppelin/contracts/utils/cryptography/MessageHashUtils.sol";

contract ClaimRedPacket is Script {
    using ECDSA for bytes32;

    function run() external {
        address redPacketAddress = vm.envAddress("REDPACKET_ADDRESS");

        RedPacket redPacket = RedPacket(redPacketAddress);

        address claimer = vm.envAddress("CLAIMER_ADDRESS");
        string memory rawPacketId = vm.envString("PACKET_ID");
        bytes32 packetId = keccak256(bytes(rawPacketId));

        bytes32 messageHash = keccak256(abi.encodePacked(claimer, packetId, block.chainid));
        bytes32 ethSignedMessageHash = MessageHashUtils.toEthSignedMessageHash(messageHash);

        (uint8 v, bytes32 r, bytes32 s) = vm.sign(vm.envUint("SIGNER_PK"), ethSignedMessageHash);
        bytes memory signature = abi.encodePacked(r, s, v);

        vm.startBroadcast();
        redPacket.claimRedPacket(packetId, signature);
        vm.stopBroadcast();
    }
}
