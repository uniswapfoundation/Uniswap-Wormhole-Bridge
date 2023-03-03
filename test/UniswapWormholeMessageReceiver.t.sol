// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "forge-std/Test.sol";
import {UniswapWormholeMessageReceiver} from "../src/UniswapWormholeMessageReceiver.sol";
import {Messages} from "wormhole/contracts/Messages.sol";
import {IWormhole} from "wormhole/contracts/interfaces/IWormhole.sol";
import "wormhole/contracts/Implementation.sol";
import "wormhole/contracts/Setup.sol";

contract UniswapWormholeMessageReceiverTest is Test {

    IWormhole public wormhole;
    IUniswapWormholeMessageReceiver public uniReceiver;

    bytes32 constant msgSender = 0x0000000000000000000000000000000000000000000000000000000000000012;

    function setUp() public {
        // set up wormhole contracts
        wormhole = IWormhole(setupWormhole());

        // set up uniswap wormhole message receiver contract
        address uniReceiverAddress = address(new UniswapWormholeMessageReceiver(address(wormhole), msgSender));
        uniReceiver = IUniswapWormholeMessageReceiver(uniReceiverAddress);
    }

    function setupWormhole() public {
        Implementation wormholeImpl = new Implementation();
        Setup wormholeSetup = new Setup();

        Wormhole wormholeAddress = new Wormhole(address(wormholeSetup), new bytes(0));

        address[] memory initSigners = new address[](1);

        for (uint256 i = 0; i < 1; ++i) {
            initSigners[i] = vm.addr(i + 1); // i+1 is the private key for the i-th signer.
        }

        // These values are the default values used in our tilt test environment
        // and are not important.
        Setup(address(wormhole)).setup(
            address(wormholeImpl),
            initSigners,
            4, // BSC chain ID
            1, // Governance source chain ID (1 = solana)
            0x0000000000000000000000000000000000000000000000000000000000000004 // Governance source address
        );
        return address(wormholeAddress);
    }

    
}
