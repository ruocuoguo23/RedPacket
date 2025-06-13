// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import "@openzeppelin/contracts/utils/cryptography/MessageHashUtils.sol";
import "@chainlink/contracts/src/v0.8/vrf/dev/VRFConsumerBaseV2Upgradeable.sol";
import "@chainlink/contracts/src/v0.8/vrf/dev/libraries/VRFV2PlusClient.sol";
import {IVRFCoordinatorV2Plus} from "@chainlink/contracts/src/v0.8/vrf/dev/interfaces/IVRFCoordinatorV2Plus.sol";


contract RedPacket is Initializable, UUPSUpgradeable, OwnableUpgradeable, VRFConsumerBaseV2Upgradeable {
    using SafeERC20 for IERC20;
    using ECDSA for bytes32;

    enum ClaimMode {
        RANDOM,
        FIXED
    }

    struct RedPacketInfo {
        address creator;
        address token;
        uint256 totalAmount;
        uint256 remainingAmount;
        uint32 totalPackets;
        uint32 claimedPackets;
        uint256 expireTime;
        ClaimMode claimMode;
        mapping(address => bool) claimed;
    }

    // Define red packet view struct for external use
    struct RedPacketView {
        address creator;
        address token;
        uint256 totalAmount;
        uint256 remainingAmount;
        uint32 totalPackets;
        uint32 claimedPackets;
        uint256 expireTime;
        ClaimMode claimMode;
        bool expired;
    }

    mapping(bytes32 => RedPacketInfo) public redPackets;
    mapping(uint256 => bytes32) private requestIdToRedPacket;
    mapping(uint256 => address) private requestIdToClaimer;

    // Chainlink VRF configuration
    uint256 private subscriptionId;
    IVRFCoordinatorV2Plus private COORDINATOR;
    bytes32 private keyHash;
    uint32 private callbackGasLimit;
    uint16 private requestConfirmations;
    uint32 private constant NUM_WORDS = 1;

    // Signer address for verifying claims
    address public signer;

    address internal constant ETH_ADDRESS = 0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE;
    uint32 public maxPacketsPerRedPacket;

    event RedPacketCreated(
        bytes32 indexed id,
        address indexed creator,
        address token,
        uint256 totalAmount,
        uint32 totalPackets,
        ClaimMode mode,
        uint256 expireTime
    );

    event RedPacketClaimed(
        bytes32 indexed id,
        address indexed claimer,
        address token,
        uint256 amount
    );

    event RedPacketRefunded(
        bytes32 indexed id,
        address indexed creator,
        address token,
        uint256 remainingAmount
    );

    event RedPacketClaimRequested(uint256 requestId, bytes32 packetId, address claimer);
    event RedPacketRandomClaimFulfilled(uint256 requestId, bytes32 indexed packetId, address indexed claimer, uint256 claimAmount);

    event SignerUpdated(address indexed oldSigner, address indexed newSigner);

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers(); // Prevent direct deployment
    }

    function initialize(
        address _vrfCoordinator,
        bytes32 _keyHash,
        uint256 _subscriptionId,
        uint32 _callbackGasLimit,
        uint16 _requestConfirmations,
        address _signer
    ) public initializer {
        __UUPSUpgradeable_init();
        __Ownable_init(msg.sender);

        // Initialize VRFConsumerBaseV2Plus
        __VRFConsumerBaseV2_init(_vrfCoordinator);

        COORDINATOR = IVRFCoordinatorV2Plus(_vrfCoordinator);
        keyHash = _keyHash;
        subscriptionId = _subscriptionId;
        callbackGasLimit = _callbackGasLimit;
        requestConfirmations = _requestConfirmations;
        signer = _signer;

        maxPacketsPerRedPacket = 500; // Default max packets
    }

    function createRedPacket(
        bytes32 packetId,
        address _token,
        uint256 _totalAmount,
        uint32 _totalPackets,
        ClaimMode _mode
    ) external payable returns (bytes32)
    {
        require(_totalPackets > 0 && _totalPackets <= maxPacketsPerRedPacket, "Invalid packet count");
        require(_totalAmount >= _totalPackets, "Total amount must be >= packet count");
        require(redPackets[packetId].creator == address(0), "Red packet ID already exists");

        RedPacketInfo storage packet = redPackets[packetId];

        packet.creator = msg.sender;
        packet.token = _token;
        packet.totalAmount = _totalAmount;
        packet.remainingAmount = _totalAmount;
        packet.totalPackets = _totalPackets;
        packet.claimedPackets = 0;
        packet.expireTime = block.timestamp + 24 hours;
        packet.claimMode = _mode;

        if (_token == ETH_ADDRESS) {
            require(msg.value == _totalAmount, "Incorrect ETH amount");
        } else {
            IERC20(_token).safeTransferFrom(msg.sender, address(this), _totalAmount);
        }

        emit RedPacketCreated(
            packetId,
            msg.sender,
            _token,
            _totalAmount,
            _totalPackets,
            _mode,
            packet.expireTime
        );

        return packetId;
    }

    function claimRedPacket(bytes32 packetId, bytes memory signature) external {
        RedPacketInfo storage packet = redPackets[packetId];
        require(block.timestamp < packet.expireTime, "Red packet expired");
        require(packet.claimedPackets < packet.totalPackets, "All packets claimed");
        require(!packet.claimed[msg.sender], "Already claimed");

        /**
         * Once a user initiates a claim, their address is immediately marked as claimed,
         * even before the Chainlink VRF callback is fulfilled.
         *
         * This design prevents malicious users from repeatedly initiating multiple
         * claim requests for the same red packet, which could otherwise result in
         * multiple VRF requests and potential abuse.
         *
         * As a trade-off, if the Chainlink VRF callback fails (e.g., due to insufficient LINK
         * or network issues), the user will not be able to claim the red packet again.
         * This is an intentional decision to prioritize fairness and protect the system
         * from abuse, even at the cost of some claim failures.
         */
        packet.claimed[msg.sender] = true;

        bytes32 messageHash = keccak256(abi.encodePacked(msg.sender, packetId, block.chainid));
        require(_verifySignature(messageHash, signature), "Invalid signature");

        uint32 remainingPackets = packet.totalPackets - packet.claimedPackets;

        if (packet.claimMode == ClaimMode.RANDOM) {
            // If remaining packets are 1, claim the remaining amount directly
            if (remainingPackets == 1) {
                _processClaim(packetId, msg.sender, packet.remainingAmount);
                return;
            } else {
                VRFV2PlusClient.RandomWordsRequest memory req = VRFV2PlusClient.RandomWordsRequest({
                    keyHash: keyHash,
                    subId: subscriptionId,
                    requestConfirmations: requestConfirmations,
                    callbackGasLimit: callbackGasLimit,
                    numWords: NUM_WORDS,
                    extraArgs: "" // empty extraArgs defaults to link payment
                });

                uint256 requestId = COORDINATOR.requestRandomWords(req);

                requestIdToRedPacket[requestId] = packetId;
                requestIdToClaimer[requestId] = msg.sender;

                emit RedPacketClaimRequested(requestId, packetId, msg.sender);
            }
        } else if (packet.claimMode == ClaimMode.FIXED) {
            uint256 claimAmount = packet.remainingAmount / (packet.totalPackets - packet.claimedPackets);
            _processClaim(packetId, msg.sender, claimAmount);
        } else {
            revert("Invalid claim mode");
        }
    }

    function fulfillRandomWords(uint256 requestId, uint256[] memory randomWords) internal override {
        bytes32 packetId = requestIdToRedPacket[requestId];
        address claimer = requestIdToClaimer[requestId];
        RedPacketInfo storage packet = redPackets[packetId];

        require(packet.remainingAmount > 0, "No remaining funds");

        uint256 claimAmount = _getRandomClaimAmount(packet, randomWords[0]);

        emit RedPacketRandomClaimFulfilled(requestId, packetId, claimer, claimAmount);
        _processClaim(packetId, claimer, claimAmount);
    }

    function _getRandomClaimAmount(RedPacketInfo storage packet, uint256 randomWord) internal view returns (uint256) {
        uint256 remainingPeople = packet.totalPackets - packet.claimedPackets;

        if (remainingPeople == 1) {
            return packet.remainingAmount;
        }

        uint256 mean = packet.remainingAmount / remainingPeople;
        uint256 max = mean * 2;

        if (max > packet.remainingAmount) {
            max = packet.remainingAmount;
        }

        uint256 claimAmount = 1 + (randomWord % (max)); // [1, max]
        return claimAmount;
    }


    function _processClaim(bytes32 packetId, address claimer, uint256 claimAmount) private {
        RedPacketInfo storage packet = redPackets[packetId];

        packet.claimedPackets++;
        packet.remainingAmount -= claimAmount;

        if (packet.token == ETH_ADDRESS) {
            (bool success, ) = claimer.call{value: claimAmount}("");
            require(success, "ETH transfer failed");
        } else {
            IERC20(packet.token).safeTransfer(claimer, claimAmount);
        }

        emit RedPacketClaimed(
            packetId,
            claimer,
            packet.token,
            claimAmount
        );
    }

    function refundExpiredPackets(bytes32 packetId) external {
        RedPacketInfo storage packet = redPackets[packetId];
        require(block.timestamp >= packet.expireTime, "Not expired yet");
        require(packet.remainingAmount > 0, "No remaining funds");

        uint256 refundAmount = packet.remainingAmount;
        packet.remainingAmount = 0;

        if (packet.token == ETH_ADDRESS) {
            (bool success, ) = packet.creator.call{value: refundAmount}("");
            require(success, "ETH transfer failed");
        } else {
            IERC20(packet.token).safeTransfer(packet.creator, refundAmount);
        }

        emit RedPacketRefunded(
            packetId,
            packet.creator,
            packet.token,
            refundAmount
        );
    }

    function updateSigner(address newSigner) external onlyOwner {
        require(newSigner != address(0), "Invalid signer address");
        address oldSigner = signer;
        signer = newSigner;
        emit SignerUpdated(oldSigner, newSigner);
    }

    function setMaxPacketsPerRedPacket(uint32 _maxPackets) external onlyOwner {
        require(_maxPackets > 0, "Invalid packet count");
        maxPacketsPerRedPacket = _maxPackets;
    }

    function setCallbackGasLimit(uint32 _callbackGasLimit) external onlyOwner {
        require(_callbackGasLimit >= 100_000, "Gas limit too low");
        callbackGasLimit = _callbackGasLimit;
    }


    function getRedPacketInfo(bytes32 packetId) external view returns (RedPacketView memory) {
        RedPacketInfo storage packet = redPackets[packetId];
        require(packet.creator != address(0), "Red packet does not exist");

        return RedPacketView({
            creator: packet.creator,
            token: packet.token,
            totalAmount: packet.totalAmount,
            remainingAmount: packet.remainingAmount,
            totalPackets: packet.totalPackets,
            claimedPackets: packet.claimedPackets,
            expireTime: packet.expireTime,
            claimMode: packet.claimMode,
            expired: block.timestamp >= packet.expireTime
        });
    }

    function _verifySignature(bytes32 messageHash, bytes memory signature) private view returns (bool) {
        return ECDSA.recover(MessageHashUtils.toEthSignedMessageHash(messageHash), signature) == signer;
    }

    function _authorizeUpgrade(address newImplementation) internal override onlyOwner {}
}
