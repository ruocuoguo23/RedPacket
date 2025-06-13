// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "../src/RedPacket.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";

contract RedPacketTest is Test {
    RedPacket public redPacket;
    MockERC20 public token;
    ERC1967Proxy public proxy;

    address public owner = address(0x1);
    address public user1 = address(0x2);
    address public user2 = address(0x3);

    // using test private key and address
    uint256 public signerPrivateKey = 0x54ea27475d60ad1c3d0f8c621acb92861879c191fa151e612f0656809630c718;
    address public signer = 0x973A66e653Fe16197994e15BBff9b8ecad30cb7C;

    bytes32 public testPacketId = keccak256("test-packet-1");

    uint256 public constant TOTAL_AMOUNT = 100 ether;
    uint32 public constant TOTAL_PACKETS = 10;
    uint32 public constant CALLBACK_GAS_LIMIT = 250000;
    uint16 public constant REQUEST_CONFIRMATIONS = 3;
    bytes32 public constant KEY_HASH = bytes32("test-key-hash");
    uint64 public constant SUBSCRIPTION_ID = 1; // ✅ Changed to uint64

    function setUp() public {
        token = new MockERC20("Test Token", "TTK", 18);

        // ✅ First mint token to owner
        token.mint(owner, TOTAL_AMOUNT);

        // ✅ Deploy proxy with owner identity (initialize will set owner)
        vm.startPrank(owner);

        RedPacket implementation = new RedPacket();

        proxy = new ERC1967Proxy(
            address(implementation),
            abi.encodeWithSelector(
                RedPacket.initialize.selector,
                address(this), // mock VRF Coordinator
                KEY_HASH,
                SUBSCRIPTION_ID,
                CALLBACK_GAS_LIMIT,
                REQUEST_CONFIRMATIONS,
                signer
            )
        );

        redPacket = RedPacket(address(proxy));

        // ✅ Owner approves token spending
        token.approve(address(redPacket), TOTAL_AMOUNT);

        vm.stopPrank();
    }

    function testCreateRedPacket() public {
        vm.startPrank(owner);
        bytes32 packetId = redPacket.createRedPacket(testPacketId, address(token), TOTAL_AMOUNT, TOTAL_PACKETS, RedPacket.ClaimMode.FIXED);
        vm.stopPrank();

        RedPacket.RedPacketView memory info = redPacket.getRedPacketInfo(packetId);
        assertEq(info.creator, owner);
        assertEq(info.token, address(token));
        assertEq(info.totalAmount, TOTAL_AMOUNT);
        assertEq(info.totalPackets, TOTAL_PACKETS);
        assertEq(uint8(info.claimMode), uint8(RedPacket.ClaimMode.FIXED));
    }

    function testClaimRedPacket() public {
        vm.startPrank(owner);
        bytes32 packetId = redPacket.createRedPacket(testPacketId, address(token), TOTAL_AMOUNT, TOTAL_PACKETS, RedPacket.ClaimMode.FIXED);
        vm.stopPrank();

        vm.startPrank(user1);
        bytes memory signature = signClaim(user1, packetId, signerPrivateKey);
        redPacket.claimRedPacket(packetId, signature);
        vm.stopPrank();
    }

    function testRefundExpiredPackets() public {
        vm.startPrank(owner);
        bytes32 packetId = redPacket.createRedPacket(testPacketId, address(token), TOTAL_AMOUNT, TOTAL_PACKETS, RedPacket.ClaimMode.FIXED);
        vm.stopPrank();

        vm.warp(block.timestamp + 25 hours);

        vm.startPrank(owner);
        redPacket.refundExpiredPackets(packetId);
        vm.stopPrank();
    }

    function testGetRedPacketInfo() public {
        vm.startPrank(owner);
        bytes32 packetId = redPacket.createRedPacket(testPacketId, address(token), TOTAL_AMOUNT, TOTAL_PACKETS, RedPacket.ClaimMode.FIXED);
        vm.stopPrank();

        RedPacket.RedPacketView memory info = redPacket.getRedPacketInfo(packetId);
        assertEq(info.creator, owner);
        assertEq(info.remainingAmount, TOTAL_AMOUNT);
        assertEq(info.claimedPackets, 0);
        assertEq(info.expired, false);
    }

    function testUpdateSigner() public {
        address newSigner = address(0xBEEF);

        vm.startPrank(owner);
        redPacket.updateSigner(newSigner);
        vm.stopPrank();

        assertEq(redPacket.signer(), newSigner);
    }

    function signClaim(address user, bytes32 packetId, uint256 privKey) internal view returns (bytes memory) {
        bytes32 messageHash = keccak256(abi.encodePacked(user, packetId, block.chainid));
        bytes32 ethSignedMessageHash = MessageHashUtils.toEthSignedMessageHash(messageHash);

        // Sign the message using Foundry's `vm.sign()`
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(privKey, ethSignedMessageHash);

        return abi.encodePacked(r, s, v);
    }
}

contract MockERC20 is ERC20 {
    constructor(string memory name, string memory symbol, uint8 decimals) ERC20(name, symbol) {}

    function mint(address to, uint256 amount) public {
        _mint(to, amount);
    }
}