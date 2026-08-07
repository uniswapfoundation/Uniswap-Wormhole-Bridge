// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.7;

import "forge-std/Script.sol";
import {UniswapWormholeMessageReceiver} from "../src/UniswapWormholeMessageReceiver.sol";

interface IWormholeGetters {
    function chainId() external view returns (uint16);
}

/**
 * @title ValidateUniswapWormholeMessageReceiver
 * @notice Validates a deployed UniswapWormholeMessageReceiver: constants, config, and initial state.
 *
 * Required env:
 *   RECEIVER_ADDRESS - Deployed UniswapWormholeMessageReceiver contract address.
 *
 * Tempo deployment expected values (used as defaults; override with env if needed):
 *   Sender contract (Ethereum): 0xf5F4496219F31CDCBa6130B5402873624585615a
 *   Tempo chain identifier:    68
 *   Wormhole Core (local):    0xbebdb6C8ddC678FfA9f8748f85C556Dd8ac6 (verified on-chain via chainId())
 *
 * Optional env overrides:
 *   EXPECTED_WORMHOLE_ADDRESS       - Default: Tempo Wormhole core above (verified on-chain).
 *   EXPECTED_MESSAGE_SENDER_ADDRESS  - Default: Tempo sender above.
 *   EXPECTED_CHAIN_ID                - Default: 68.
 *
 * Example:
 *   RECEIVER_ADDRESS=0x... forge script script/ValidateUniswapWormholeMessageReceiver.s.sol --rpc-url <RPC>
 */
contract ValidateUniswapWormholeMessageReceiver is Script {
    address constant DEFAULT_EXPECTED_MESSAGE_SENDER = 0xf5F4496219F31CDCBa6130B5402873624585615a;
    address constant DEFAULT_EXPECTED_WORMHOLE = 0xbebdb6C8ddC678FfA9f8748f85C815C556Dd8ac6;
    uint256 constant DEFAULT_EXPECTED_CHAIN_ID = 68;

    // Must match UniswapWormholeMessageReceiver.EXPECTED_MESSAGE_PAYLOAD_VERSION
    bytes32 constant EXPECTED_PAYLOAD_VERSION = keccak256(
        abi.encode(
            "UniswapWormholeMessageSenderV1 (bytes32 receivedMessagePayloadVersion, address[] memory targets, uint256[] memory values, bytes[] memory datas, address messageReceiver, uint16 receiverChainId)"
        )
    );

    function run() external {
        address receiverAddress = vm.envAddress("RECEIVER_ADDRESS");
        UniswapWormholeMessageReceiver receiver = UniswapWormholeMessageReceiver(receiverAddress);

        console.log("Validating UniswapWormholeMessageReceiver at", receiverAddress);
        console.log("");

        uint256 failures = 0;

        // --- Wormhole Core (on-chain verification via chainId()) ---
        uint256 expectedChainIdRaw = vm.envOr("EXPECTED_CHAIN_ID", DEFAULT_EXPECTED_CHAIN_ID);
        require(expectedChainIdRaw <= type(uint16).max, "EXPECTED_CHAIN_ID out of range");
        uint16 expectedChainId = uint16(expectedChainIdRaw);

        // Wormhole Core (on-chain verification via chainId()). Use --fork-url so the script sees chain state.
        address expectedWormhole = vm.envOr("EXPECTED_WORMHOLE_ADDRESS", DEFAULT_EXPECTED_WORMHOLE);
        try IWormholeGetters(expectedWormhole).chainId() returns (uint16 wormholeChainId) {
            if (wormholeChainId != expectedChainId) {
                console.log("[FAIL] Wormhole chainId mismatch");
                console.log("  actual:  ", uint256(wormholeChainId));
                console.log("  expected:", uint256(expectedChainId));
                failures++;
            } else {
                console.log("[OK] Wormhole verified at", expectedWormhole);
                console.log("  chainId:", uint256(expectedChainId));
            }
        } catch {
            console.log("[FAIL] Wormhole not reachable at", expectedWormhole);
            console.log("  (Use --fork-url <TEMPO_RPC> so the script runs against chain state)");
            failures++;
        }

        // --- Constants ---
        if (keccak256(bytes(receiver.NAME())) != keccak256(bytes("Uniswap Wormhole Message Receiver"))) {
            console.log("[FAIL] NAME");
            failures++;
        } else {
            console.log("[OK] NAME");
        }

        if (receiver.EXPECTED_MESSAGE_PAYLOAD_VERSION() != EXPECTED_PAYLOAD_VERSION) {
            console.log("[FAIL] EXPECTED_MESSAGE_PAYLOAD_VERSION");
            failures++;
        } else {
            console.log("[OK] EXPECTED_MESSAGE_PAYLOAD_VERSION");
        }

        // ETHEREUM_CHAIN_ID is the contract constant for source chain (Ethereum = 2), not this chain
        if (receiver.ETHEREUM_CHAIN_ID() != 2) {
            console.log("[FAIL] ETHEREUM_CHAIN_ID constant (must be 2 = Ethereum source chain)");
            failures++;
        } else {
            console.log("[OK] ETHEREUM_CHAIN_ID (Ethereum = 2)");
        }

        if (receiver.MESSAGE_TIME_OUT_SECONDS() != 2 days) {
            console.log("[FAIL] MESSAGE_TIME_OUT_SECONDS (expected 2 days)");
            failures++;
        } else {
            console.log("[OK] MESSAGE_TIME_OUT_SECONDS");
        }

        // --- Config (immutables) ---
        bytes32 messageSender = receiver.messageSender();
        uint16 chainId = receiver.chainId();
        console.log("[INFO] messageSender (bytes32):", vm.toString(messageSender));
        console.log("[INFO] chainId:", chainId);

        // forge-lint: disable-next-line unsafe-typecast -- high 12 bytes must be zero (Wormhole format)
        if (bytes12(messageSender) != bytes12(0)) {
            console.log("[FAIL] messageSender must have 12 leading zero bytes (Wormhole format)");
            failures++;
        } else {
            console.log("[OK] messageSender Wormhole format (12 zero bytes + address)");
        }

        // Assert against expected config (Tempo defaults; override with env)
        address expectedSender = vm.envOr("EXPECTED_MESSAGE_SENDER_ADDRESS", DEFAULT_EXPECTED_MESSAGE_SENDER);
        bytes32 expectedMessageSender = bytes32(uint256(uint160(expectedSender)));
        if (messageSender != expectedMessageSender) {
            console.log("[FAIL] messageSender does not match expected (Tempo sender or EXPECTED_MESSAGE_SENDER_ADDRESS)");
            failures++;
        } else {
            console.log("[OK] messageSender matches expected");
        }

        if (chainId != expectedChainId) {
            console.log("[FAIL] chainId mismatch (expected Tempo = 68)");
            console.log("  actual:  ", uint256(chainId));
            console.log("  expected:", uint256(expectedChainId));
            failures++;
        } else {
            console.log("[OK] chainId ==", expectedChainId);
        }

        // --- Initial / current state ---
        uint64 nextSeq = receiver.nextMinimumSequence();
        console.log("[INFO] nextMinimumSequence:", nextSeq);
        if (nextSeq != 0) {
            console.log("[INFO] (nextMinimumSequence != 0: deployment may have already processed messages)");
        }

        console.log("");
        if (failures > 0) {
            console.log("Validation FAILED with", failures);
            console.log("failure(s)");
            revert("Validation failed");
        }
        console.log("Validation PASSED");
    }
}
