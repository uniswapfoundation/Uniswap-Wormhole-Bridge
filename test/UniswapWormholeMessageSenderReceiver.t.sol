// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "forge-std/Test.sol";
import {UniswapWormholeMessageReceiver} from "../src/UniswapWormholeMessageReceiver.sol";
import {IUniswapWormholeMessageReceiver} from "../src/interfaces/IUniswapWormholeMessageReceiver.sol";
import {UniswapWormholeMessageSender} from "../src/UniswapWormholeMessageSender.sol";
import {IUniswapWormholeMessageSender} from "../src/interfaces/IUniswapWormholeMessageSender.sol";
import {Messages} from "wormhole/contracts/Messages.sol";
import {IWormhole} from "wormhole/contracts/interfaces/IWormhole.sol";
import "wormhole/contracts/Implementation.sol";
import "wormhole/contracts/Setup.sol";
import {Wormhole} from "wormhole/contracts/Wormhole.sol";

contract UniswapWormholeMessageSenderReceiverTest is Test {

    IWormhole public wormhole;
    IUniswapWormholeMessageReceiver public uniReceiver;
    IUniswapWormholeMessageSender public uniSender;

    bytes32 constant msgSender = 0x0000000000000000000000000000000000000000000000000000000000000012;
    uint256 constant numGuardians = 19;
    uint256 constant quorumGuardians = 13;
    uint256 timestamp = 1641070800;
    uint16 ethereum_chain_id = 2;
    uint16 bsc_chain_id = 4;

    address[] targets;
    uint256[] values;
    bytes[] datas;
    address[] incorrectLengthTargets;

    function setUp() public {
        // set up wormhole contracts
        wormhole = IWormhole(setupWormhole());

        // set up uniswap wormhole message receiver contract
        address uniReceiverAddress = address(new UniswapWormholeMessageReceiver(address(wormhole), msgSender));
        uniReceiver = IUniswapWormholeMessageReceiver(uniReceiverAddress);

        // set up uniswap wormhole message sender contract
        address uniSenderAddress = address(new UniswapWormholeMessageSender(address(wormhole)));
        uniSender = IUniswapWormholeMessageSender(uniSenderAddress);

        targets.push(vm.addr(8)); // filling with a likely EOA for now
        values.push(0);
        datas.push(abi.encodePacked("random")); // setting to a random byte as target is set to an EOA for now
    }

    function setupWormhole() public returns(address) {
        Implementation wormholeImpl = new Implementation();
        Setup wormholeSetup = new Setup();

        Wormhole wormholeAddress = new Wormhole(address(wormholeSetup), new bytes(0));

        address[] memory initSigners = new address[](numGuardians);

        for (uint256 i = 0; i < numGuardians; ++i) {
            initSigners[i] = vm.addr(i + 1); // i+1 is the private key for the i-th signer.
        }

        // These values are the default values used in our tilt test environment
        // and are not important.
        Setup(address(wormholeAddress)).setup(
            address(wormholeImpl),
            initSigners,
            bsc_chain_id, // BSC chain ID
            1, // Governance source chain ID (1 = solana)
            0x0000000000000000000000000000000000000000000000000000000000000004, // Governance source address
            block.chainid // evm chain Id
        );
        return address(wormholeAddress);
    }

    function generateSignedVaa(uint16 emitterChainId, bytes32 emitterAddress, uint64 sequence, bytes memory payload) public returns(bytes memory vaa) {
        vm.warp(timestamp);

        bytes memory body = abi.encodePacked(
            uint32(block.timestamp),
            uint32(0), //nonce is zero
            emitterChainId, //emitter chain id for ethereum is 2
            emitterAddress, //expected emitter address
            sequence, //sequence
            uint8(1), //consistency level
            payload
        );

        bytes32 hash = keccak256(abi.encodePacked(keccak256(body)));

        bytes memory signatures = new bytes(0);

        for (uint256 i = 0; i < quorumGuardians; ++i) {
            (uint8 v, bytes32 r, bytes32 s) = vm.sign(i + 1, hash);
            signatures = abi.encodePacked(
                signatures,
                uint8(i), // Guardian index of the signature
                r,
                s,
                v - 27 // v is either 27 or 28. 27 is added to v in Eth (following BTC) but Wormhole doesn't use it.
            );
        }

        vaa = abi.encodePacked(
            uint8(1), // Version
            uint32(0), // Guardian set index. it is initialized by 0
            uint8(quorumGuardians),
            signatures,
            body
        );
    }

    function generateMessagePayload(address[] memory targetValues, uint256[] memory msgValues, bytes[] memory dataValues, uint16 receiverChainId, address receiverAddress) public returns(bytes memory payload) {
       payload = abi.encode(targetValues, msgValues, dataValues, bytes32(uint256(uint160(receiverAddress))), receiverChainId);
    }

    function testSendMessageSuccess() public {
        uniSender.sendMessage(targets, values, datas, address(uniReceiver), bsc_chain_id);
    }

    function testReceiveMessageSuccess() public {
        uint64 sequence = 1;
        uint16 emitterChainId = 2;

        bytes memory payload = generateMessagePayload(targets, values, datas, bsc_chain_id, address(uniReceiver));
        bytes memory whMessage = generateSignedVaa(emitterChainId, msgSender, sequence, payload);

        vm.warp(timestamp + 45 minutes);
        uniReceiver.receiveMessage(whMessage);
    }

    function testInvalidEmitterAddress() public {
        uint64 sequence = 1;

        bytes memory payload = generateMessagePayload(targets, values, datas, bsc_chain_id, address(uniReceiver));
        bytes memory whMessage = generateSignedVaa(ethereum_chain_id, bytes32(uint256(8)), sequence, payload);

        vm.warp(timestamp + 45 minutes);
        vm.expectRevert("Invalid Emitter Address!");
        uniReceiver.receiveMessage(whMessage);
    }

    function testInvalidEmitterChainId() public {
        uint64 sequence = 1;

        bytes memory payload = generateMessagePayload(targets, values, datas, bsc_chain_id, address(uniReceiver));
        bytes memory whMessage = generateSignedVaa(ethereum_chain_id - 1, msgSender, sequence, payload);

        vm.warp(timestamp + 45 minutes);
        vm.expectRevert("Invalid Emitter Chain");
        uniReceiver.receiveMessage(whMessage);
    }

    function testReplay() public {
        uint64 sequence = 1;

        bytes memory payload = generateMessagePayload(targets, values, datas, bsc_chain_id, address(uniReceiver));
        bytes memory whMessage = generateSignedVaa(ethereum_chain_id, msgSender, sequence, payload);

        vm.warp(timestamp + 45 minutes);
        uniReceiver.receiveMessage(whMessage);

        vm.expectRevert("Invalid Sequence number");
        uniReceiver.receiveMessage(whMessage);
    }

    function testInvalidSequence() public {
        uint64 sequence = 2;

        bytes memory payload = generateMessagePayload(targets, values, datas, bsc_chain_id, address(uniReceiver));
        bytes memory whMessage = generateSignedVaa(ethereum_chain_id, msgSender, sequence, payload);

        vm.warp(timestamp + 45 minutes);
        uniReceiver.receiveMessage(whMessage);

        whMessage = generateSignedVaa(ethereum_chain_id, msgSender, sequence - 1, payload);

        vm.expectRevert("Invalid Sequence number");
        uniReceiver.receiveMessage(whMessage);
    }

    function testMessageTimeout() public {
        uint64 sequence = 2;

        bytes memory payload = generateMessagePayload(targets, values, datas, bsc_chain_id, address(uniReceiver));
        bytes memory whMessage = generateSignedVaa(ethereum_chain_id, msgSender, sequence, payload);

        vm.warp(timestamp + 2881 minutes);
        vm.expectRevert("Message no longer valid");
        uniReceiver.receiveMessage(whMessage);
    }

    function testInconsistentPayload() public {
        uint64 sequence = 2;

        bytes memory payload = generateMessagePayload(incorrectLengthTargets, values, datas, bsc_chain_id, address(uniReceiver));
        bytes memory whMessage = generateSignedVaa(ethereum_chain_id, msgSender, sequence, payload);

        vm.warp(timestamp + 45 minutes);
        vm.expectRevert("Inconsistent argument lengths");
        uniReceiver.receiveMessage(whMessage);
    }

    function testInvalidReceiverAddress() public {
        uint64 sequence = 2;

        bytes memory payload = generateMessagePayload(targets, values, datas, bsc_chain_id, address(uint160(2023)));
        bytes memory whMessage = generateSignedVaa(ethereum_chain_id, msgSender, sequence, payload);

        vm.warp(timestamp + 45 minutes);
        vm.expectRevert("Message not for this dest");
        uniReceiver.receiveMessage(whMessage);
    }

    function testInvalidReceiverChain() public {
        uint64 sequence = 2;

        bytes memory payload = generateMessagePayload(targets, values, datas, bsc_chain_id - 1, address(uniReceiver));
        bytes memory whMessage = generateSignedVaa(ethereum_chain_id, msgSender, sequence, payload);

        vm.warp(timestamp + 45 minutes);
        vm.expectRevert("Message not for this chain");
        uniReceiver.receiveMessage(whMessage);
    }

    function testFailingSubcall() public {
        uint64 sequence = 2;

        address[] memory failingTargets = new address[](1);
        failingTargets[0] = 0xb4c79daB8f259C7Aee6E5b2Aa729821864227e84;

        bytes memory payload = generateMessagePayload(failingTargets, values, datas, bsc_chain_id - 1, address(uniReceiver));
        bytes memory whMessage = generateSignedVaa(ethereum_chain_id, msgSender, sequence, payload);

        vm.warp(timestamp + 45 minutes);
        vm.expectRevert("Sub-call failed");
        uniReceiver.receiveMessage(whMessage);
    }


}