// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.7;

import "forge-std/Script.sol";
import {UniswapWormholeMessageReceiver} from "../src/UniswapWormholeMessageReceiver.sol";

/**
 * @title DeployUniswapWormholeMessageReceiver
 * @notice Deploys UniswapWormholeMessageReceiver. Uses Tempo defaults below; override with env vars.
 *
 * Tempo deployment defaults:
 *   Wormhole Core Bridge (local): 0xbebdb6C8ddC678FfA9f8748f85C815C556Dd8ac6
 *   Sender contract (Ethereum):   0xf5F4496219F31CDCBa6130B5402873624585615a
 *   Tempo chain identifier:      68
 *
 * Optional env overrides:
 *   WORMHOLE_ADDRESS          - Wormhole core on this chain (default: Tempo Wormhole Core Bridge)
 *   MESSAGE_SENDER_ADDRESS    - UniswapWormholeMessageSender on Ethereum (default: above)
 *   CHAIN_ID                  - Wormhole chain ID of this chain (default: 68)
 *
 * Example:
 *   forge script script/DeployUniswapWormholeMessageReceiver.s.sol --rpc-url <RPC> --broadcast
 */
contract DeployUniswapWormholeMessageReceiver is Script {
    address constant DEFAULT_WORMHOLE = 0xbebdb6C8ddC678FfA9f8748f85C815C556Dd8ac6;
    address constant DEFAULT_MESSAGE_SENDER = 0xf5F4496219F31CDCBa6130B5402873624585615a;
    uint256 constant DEFAULT_CHAIN_ID = 68;

    function run() external returns (UniswapWormholeMessageReceiver receiver) {
        address wormholeAddress = vm.envOr("WORMHOLE_ADDRESS", DEFAULT_WORMHOLE);
        address messageSenderAddress = vm.envOr("MESSAGE_SENDER_ADDRESS", DEFAULT_MESSAGE_SENDER);
        uint16 chainId = uint16(vm.envOr("CHAIN_ID", DEFAULT_CHAIN_ID));

        // Wormhole format: 12 zero bytes followed by 20-byte Ethereum address
        bytes32 messageSender = bytes32(uint256(uint160(messageSenderAddress)));

        vm.startBroadcast();
        receiver = new UniswapWormholeMessageReceiver(wormholeAddress, messageSender, chainId);
        vm.stopBroadcast();

        console.log("UniswapWormholeMessageReceiver deployed at", address(receiver));
        console.log("  wormhole:     ", wormholeAddress);
        console.log("  messageSender:", vm.toString(messageSender));
        console.log("  chainId:      ", chainId);
    }
}
