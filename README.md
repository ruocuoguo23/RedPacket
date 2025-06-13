# Chainlink VRF Red Packet Smart Contract

A decentralized red packet (lucky money) distribution system built on Ethereum using Chainlink VRF for verifiable random distribution. This contract allows users to create and claim digital red packets with either ETH or any ERC20 token.

## Features

- **Two Distribution Modes**:
  - **Random Mode**: Recipients receive random amounts (using Chainlink VRF)
  - **Fixed Mode**: Recipients receive equal amounts
- **Token Support**:
  - Native ETH
  - Any ERC20 token
- **Security & Reliability**:
  - Signature-based claiming mechanism
  - Time-limited availability (24-hour expiration)
  - Refund mechanism for unclaimed funds
  - UUPS upgradeable contract pattern
  - Chainlink VRF for verifiable randomness

## Architecture

- **RedPacket.sol**: Main contract implementing the red packet functionality
- **Deployment Scripts**:
  - `DeployRedPacket.s.sol`: Deploys implementation and proxy contracts
  - `UpgradeRedPacket.s.sol`: Upgrades the implementation contract
  - `UpdateSigner.s.sol`: Updates the signature verification address

## Prerequisites

- [Foundry](https://book.getfoundry.sh/) development environment
- Chainlink VRF subscription
- Access to Ethereum RPC endpoints

## Setup & Deployment

### Install Dependencies

```shell
$ forge install
```

### Environment Variables

Create a `.env` file with the following variables:

```
OWNER_ADDRESS=<your-wallet-address>
VRF_COORDINATOR=<chainlink-vrf-coordinator-address>
VRF_KEY_HASH=<vrf-key-hash-for-your-network>
VRF_SUBSCRIPTION_ID=<your-subscription-id>
SIGNER_ADDRESS=<address-for-verifying-signatures>
```

### Deploy the Contract

```shell
$ source .env
$ forge script script/deploy/DeployRedPacket.s.sol --rpc-url <your_rpc_url> --private-key <your_private_key> --broadcast
```

### Upgrade the Contract

```shell
$ export PROXY_ADDRESS=<your-deployed-proxy-address>
$ forge script script/deploy/UpgradeRedPacket.s.sol --rpc-url <your_rpc_url> --private-key <your_private_key> --broadcast
```

### Update the Signer

```shell
$ export REDPACKET_ADDRESS=<your-deployed-proxy-address>
$ export NEW_SIGNER=<new-signer-address>
$ forge script script/deploy/UpdateSigner.s.sol --rpc-url <your_rpc_url> --private-key <your_private_key> --broadcast
```

## Usage Guide

### Creating a Red Packet

To create a red packet, you need to:

1. Generate a unique packet ID
2. Specify the token (ETH or ERC20)
3. Define total amount and number of packets
4. Choose distribution mode (random or fixed)

**ETH Red Packet Example**:
```solidity
// Generate a unique packet ID
bytes32 packetId = keccak256(abi.encodePacked("my-unique-id", block.timestamp, msg.sender));

// Create ETH red packet with 1 ETH divided into 10 random packets
redPacket.createRedPacket{value: 1 ether}(
    packetId,
    0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE, // ETH address constant
    1 ether,
    10,
    RedPacket.ClaimMode.RANDOM
);
```

**ERC20 Red Packet Example**:
```solidity
// First approve the contract to spend your tokens
IERC20(tokenAddress).approve(address(redPacket), tokenAmount);

// Create token red packet with fixed distribution
redPacket.createRedPacket(
    packetId,
    tokenAddress,
    tokenAmount,
    5,
    RedPacket.ClaimMode.FIXED
);
```

### Signature-Based Claiming Mechanism

This contract uses a signature-based claiming mechanism (similar to a password red packet system) to prevent bot attacks and ensure only authorized users can claim red packets:

1. **Setup**: During contract deployment, a signer address is specified. This address corresponds to a private key that will be used to generate signatures.

2. **Backend Infrastructure**: 
   - The signer's private key should be securely stored on a centralized backend server
   - Users request a signature from this backend server to claim a red packet
   - The backend can enforce business rules (e.g., KYC verification, rate limiting) before issuing signatures

3. **Signature Generation Process**:
   - The backend signs a message containing: `keccak256(abi.encodePacked(userAddress, packetId, chainId))`
   - This creates a unique signature that links a specific user to a specific red packet on a specific chain
   - The signature can only be used once as the contract tracks claims

4. **Security Benefits**:
   - Prevents bot attacks and sybil attacks
   - Enables control over who can claim red packets
   - Allows for custom distribution strategies through backend logic

5. **Updating the Signer**: The contract owner can update the signer address if needed using the `updateSigner` function.

### Claiming a Red Packet

Users need a valid signature to claim a red packet:

1. Generate signature off-chain by signing:
   ```
   keccak256(abi.encodePacked(userAddress, packetId, chainId))
   ```
   
2. Call the claim function:
   ```solidity
   redPacket.claimRedPacket(packetId, signature);
   ```

### Refunding Expired Red Packets

After the 24-hour expiry period, creators can recover unclaimed funds:

```solidity
redPacket.refundExpiredPackets(packetId);
```

## Testing

Run the complete test suite:

```shell
$ forge test
```

With gas reporting:

```shell
$ forge test --gas-report
```

## Foundry Commands

### Build

```shell
$ forge build
```

### Format

```shell
$ forge fmt
```

### Gas Snapshots

```shell
$ forge snapshot
```

### Local Development

```shell
$ anvil
```

### Help

```shell
$ forge --help
$ anvil --help
$ cast --help
```

## Security Considerations

- The random distribution relies on Chainlink VRF for verifiable randomness
- Signature verification prevents unauthorized claims
- The contract follows best security practices:
  - Checks-Effects-Interactions pattern
  - Protection against re-entrancy
  - Proper validation of user inputs
  - Prevention of multiple claims by the same user

## License

MIT
