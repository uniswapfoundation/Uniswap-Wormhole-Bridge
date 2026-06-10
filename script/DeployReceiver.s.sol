// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.12;

import {Script, console} from "../lib/forge-std/src/Script.sol";

import {UniswapWormholeMessageReceiver} from "../src/UniswapWormholeMessageReceiver.sol";

/// @title Deployer of UniswapWormholeMessageReceiver
/// @dev `WORMHOLE_CORE` is required; it is the wormhole bridge address on the remote chain.
/// @dev `WORMHOLE_CHAIN_ID` is required; it is the wormhole-defined chain id for the remote chain.
/// @dev `MESSAGE_SENDER` is optional, as we use one unified sender on Ethereum.
contract DeployReceiver is Script {
    uint16 internal constant WORMHOLE_ETHEREUM_CHAIN_ID = 2;

    function run() external {
        // -----------------------------------------------------------------------------------------
        // Load environment variables
        //
        address messageSender = vm.envOr(
            "MESSAGE_SENDER",
            0xf5F4496219F31CDCBa6130B5402873624585615a
        );
        address wormholeCore = vm.envAddress("WORMHOLE_CORE");
        uint16 wormholeChainId = uint16(vm.envUint("WORMHOLE_CHAIN_ID"));

        bytes32 wormholeMessageSender = bytes32(uint256(uint160(messageSender)));

        // -----------------------------------------------------------------------------------------
        // Deploy the receiver contract.
        //
        vm.startBroadcast();
        UniswapWormholeMessageReceiver receiver = new UniswapWormholeMessageReceiver({
                wormholeAddress: wormholeCore,
                _messageSender: wormholeMessageSender,
                _chainId: wormholeChainId
            });
        vm.stopBroadcast();

        // -----------------------------------------------------------------------------------------
        // Smoke check the deployment.
        //
        require(
            receiver.messageSender() == wormholeMessageSender,
            "mismatch: messageSender"
        );
        require(receiver.chainId() == wormholeChainId, "mismatch: chainId");
        require(
            receiver.ETHEREUM_CHAIN_ID() == WORMHOLE_ETHEREUM_CHAIN_ID,
            "mismatch: ETHEREUM_CHAIN_ID"
        );
        require(
            receiver.nextMinimumSequence() == 0,
            "mismatch: nextMinimumSequence"
        );
        require(
            receiver.MESSAGE_TIME_OUT_SECONDS() == 2 days,
            "mismatch: MESSAGE_TIME_OUT_SECONDS"
        );

        // -----------------------------------------------------------------------------------------
        // Log the output.
        //
        console.logString(
            string.concat(
                "Deployed UniswapWormholeMessageReceiver",
                "\naddress (target chain):           ",
                vm.toString(address(receiver)),
                "\neip-155 chain id (target chain):  ",
                vm.toString(block.chainid),
                "\nwormhole chain id (target chain): ",
                vm.toString(wormholeChainId),
                "\nmessage sender (ethereum):        ",
                vm.toString(messageSender),
                "\nwormhole core (target chain):     ",
                vm.toString(wormholeCore)
            )
        );
    }
}
