// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.12;

import {Script, console} from "../lib/forge-std/src/Script.sol";

import {UniswapWormholeMessageReceiver} from "../src/UniswapWormholeMessageReceiver.sol";
import {Constants} from "./Constants.sol";

/// @title Deployer of UniswapWormholeMessageReceiver
/// @dev Note that the `Constants.smokeCheck()` will revert if the approproate variables have not
///      been set in the `script/Constants.sol` file.
contract DeployReceiver is Script {
    function run() external {
        vm.startBroadcast();
        // -----------------------------------------------------------------------------------------
        // Ensure all constants are set for this deployment.
        //
        Constants.smokeCheck();

        bytes32 messageSender = bytes32(
            uint256(uint160(Constants.MESSAGE_SENDER))
        );

        // -----------------------------------------------------------------------------------------
        // Deploy the receiver contract.
        //
        UniswapWormholeMessageReceiver receiver = new UniswapWormholeMessageReceiver({
                wormholeAddress: Constants.WORMHOLE_CORE,
                _messageSender: messageSender,
                _chainId: Constants.WORMHOLE_CHAIN_ID
            });

        // -----------------------------------------------------------------------------------------
        // Smoke check the deployment.
        //
        require(
            receiver.messageSender() == messageSender,
            "mismatch: messageSender"
        );
        require(
            receiver.chainId() == Constants.WORMHOLE_CHAIN_ID,
            "mismatch: chainId"
        );
        require(
            receiver.ETHEREUM_CHAIN_ID() ==
                Constants.WORMHOLE_ETHEREUM_CHAIN_ID,
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
                vm.toString(Constants.WORMHOLE_CHAIN_ID),
                "\nmessage sender (ethereum):        ",
                vm.toString(Constants.MESSAGE_SENDER),
                "\nwormhole core (target chain):     ",
                vm.toString(Constants.WORMHOLE_CORE)
            )
        );
        vm.stopBroadcast();
    }
}
