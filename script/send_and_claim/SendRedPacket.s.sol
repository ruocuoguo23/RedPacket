// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Script.sol";
import "../../src/RedPacket.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

contract SendRedPacket is Script {
    function run() external {
        address redPacketAddress = vm.envAddress("REDPACKET_ADDRESS");
        address tokenAddress = vm.envAddress("TOKEN_ADDRESS");

        RedPacket redPacket = RedPacket(redPacketAddress);

        string memory rawPacketId = vm.envString("PACKET_ID");
        bytes32 packetId = keccak256(bytes(rawPacketId));

        uint256 totalAmount = 0.00001 ether;
        uint32 totalPackets = 2;

        address ETH_ADDRESS = 0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE;

        vm.startBroadcast();

        if (tokenAddress == ETH_ADDRESS) {
            // Send ETH red packet
            redPacket.createRedPacket{value: totalAmount}(
                packetId,
                tokenAddress,
                totalAmount,
                totalPackets,
                RedPacket.ClaimMode.RANDOM
            );
        } else {
            // Send ERC20 red packet
            IERC20 token = IERC20(tokenAddress);
            token.approve(address(redPacket), totalAmount);

            redPacket.createRedPacket(
                packetId,
                tokenAddress,
                totalAmount,
                totalPackets,
                RedPacket.ClaimMode.RANDOM
            );
        }

        vm.stopBroadcast();
    }
}
