// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "forge-std/Test.sol";
import "../src/UniswapWormholeMessageReceiver.sol";

contract UniswapWormholeMessageReceiverTest is Test {
    UniswapWormholeMessageReceiver receiver;

    // The state of the contract gets reset before each
    // test is run, with the `setUp()` function being called
    // each time after deployment.
    function setUp() public {
        bytes32 messageSender;
        address bridgeAddress;
        receiver = new UniswapWormholeMessageReceiver(bridgeAddress, messageSender);
    }

    // A test to ensure our constants remain locked in
    function testConstants() public {
        require(receiver.ETHEREUM_CHAIN_ID() == 2, "ETHEREUM_CHAIN_ID should be 2");
        require(receiver.BSC_CHAIN_ID() == 4, "BSC_CHAIN_ID should be 4");
        require(receiver.MESSAGE_TIME_OUT_SECONDS() == 3600, "MESSAGE_TIME_OUT_SECONDS should be 3600");
    }
}