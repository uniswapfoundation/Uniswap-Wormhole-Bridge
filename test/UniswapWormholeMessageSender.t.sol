// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "forge-std/Test.sol";
import "../src/UniswapWormholeMessageSender.sol";

contract UniswapWormholeMessageSenderTest is Test {
    UniswapWormholeMessageSender sender;

    // The state of the contract gets reset before each
    // test is run, with the `setUp()` function being called
    // each time after deployment.
    function setUp() public {
        address bridgeAddress;
        sender = new UniswapWormholeMessageSender(bridgeAddress);
    }

    // A test to ensure our constants remain locked in
    function testConstants() public {
        require(sender.NONCE() == 0, "NONCE should be 0");
        require(sender.CONSISTENCY_LEVEL() == 1, "CONSISTENCY_LEVEL should be 1");
    }
}