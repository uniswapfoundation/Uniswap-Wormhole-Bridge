// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "forge-std/Test.sol";
import {UniswapWormholeMessageReceiver} from "../src/UniswapWormholeMessageReceiver.sol";
import {IUniswapWormholeMessageReceiver} from "../src/interfaces/IUniswapWormholeMessageReceiver.sol";
import {UniswapWormholeMessageSender, generateMessagePayload} from "../src/UniswapWormholeMessageSender.sol";
import {IUniswapWormholeMessageSender} from "../src/interfaces/IUniswapWormholeMessageSender.sol";
import {Messages} from "wormhole/contracts/Messages.sol";
import {IWormhole} from "wormhole/contracts/interfaces/IWormhole.sol";
import "wormhole/contracts/Implementation.sol";
import "wormhole/contracts/Setup.sol";
import {Wormhole} from "wormhole/contracts/Wormhole.sol";
import {MockGovernanceReceiver} from "./MockGovernanceReceiver.sol";

interface IMockGovernanceReceiver {
    function governanceValueOne() external returns (uint256);
    function governanceValueTwo() external returns (uint256);
    function consumedActions(bytes32 action) external returns (bool);
}

contract UniswapWormholeMessageSenderReceiverTest is Test {
    IWormhole public wormhole;
    IUniswapWormholeMessageReceiver public uniReceiver;
    IUniswapWormholeMessageSender public uniSender;
    IMockGovernanceReceiver public mock;

    // Mock governance actions
    bytes32 constant governanceActionOne = 0x0000000000000000000000000000000000000000000000000000000000000069;
    bytes32 constant governanceActionTwo = 0x000000000000000000000000000000000000000000000000000000000000beef;

    // Test setup variables
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

        // deploy the mock governance contract
        address mockReceiver = address(new MockGovernanceReceiver(uniReceiverAddress));
        mock = IMockGovernanceReceiver(mockReceiver);

        // set up uniswap wormhole message sender contract
        address uniSenderAddress = address(new UniswapWormholeMessageSender(address(wormhole)));
        uniSender = IUniswapWormholeMessageSender(uniSenderAddress);

        // create calldata for the first mock governance action
        bytes memory encodedGovernanceActionOne =
            abi.encodeWithSignature("receiveGovernanceMessageOne(bytes32,uint8)", governanceActionOne, 1);

        targets.push(mockReceiver);
        values.push(mock.governanceValueOne());
        datas.push(encodedGovernanceActionOne);
    }

    function setupWormhole() public returns (address) {
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

    function expectRevertWithValue(
        address contractAddress,
        bytes memory encodedSignature,
        string memory expectedRevert,
        uint256 value_
    ) internal {
        (bool success, bytes memory result) = contractAddress.call{value: value_}(encodedSignature);
        require(!success, "call did not revert");

        // fetch the revert string bytes
        bytes memory newResult;
        for (uint256 i = 0; i < result.length; ++i) {
            // skip signature
            if (i > 3) {
                newResult = abi.encodePacked(newResult, result[i]);
            }
        }

        // compare revert strings
        bytes32 expectedRevertHash = keccak256(abi.encode(expectedRevert));
        bytes32 actualRevertHash = keccak256(newResult);
        require(expectedRevertHash == actualRevertHash, "call did not revert as expected");
    }

    function simulateSignedVaa(bytes memory body, bytes32 _hash) internal pure returns (bytes memory vaa) {
        bytes memory signatures = new bytes(0);

        for (uint256 i = 0; i < quorumGuardians; ++i) {
            (uint8 v, bytes32 r, bytes32 s) = vm.sign(i + 1, _hash);
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

    function generateSignedVaa(uint16 emitterChainId, bytes32 emitterAddress, uint64 sequence, bytes memory payload)
        public
        returns (bytes memory)
    {
        vm.warp(timestamp);

        // format the message body
        bytes memory body = abi.encodePacked(
            uint32(block.timestamp),
            uint32(0), //nonce is zero
            emitterChainId, //emitter chain id for ethereum is 2
            emitterAddress, //expected emitter address
            sequence, //sequence
            uint8(1), //consistency level
            payload
        );

        // compute the hash of the body
        bytes32 _hash = keccak256(abi.encodePacked(keccak256(body)));

        // return the signed VAA
        return simulateSignedVaa(body, _hash);
    }

    function updateWormholeMessageFee(uint256 newFee) public {
        bytes32 coreModule = 0x00000000000000000000000000000000000000000000000000000000436f7265;

        // `SetMessageFee` governance payload
        bytes memory payload = abi.encodePacked(coreModule, uint8(3), uint16(wormhole.chainId()), newFee);

        // construct the `SetMessageFee` governance VAA
        bytes memory body = abi.encodePacked(
            uint32(block.timestamp),
            uint32(0), //nonce is zero
            uint16(1), //governance chain
            bytes32(0x0000000000000000000000000000000000000000000000000000000000000004), //governance contract
            uint64(0), //sequence
            uint8(1), //consistency level
            payload
        );

        // compute the hash of the body
        bytes32 _hash = keccak256(abi.encodePacked(keccak256(body)));

        // update the message fee
        wormhole.submitSetMessageFee(simulateSignedVaa(body, _hash));
    }

    function testUpdateWormholeMessageFee(uint256 newFee) public {
        uint256 currentFee = wormhole.messageFee();

        vm.assume(currentFee != newFee);

        updateWormholeMessageFee(newFee);

        // verify the state change
        currentFee = wormhole.messageFee();
        assertEq(currentFee, newFee);
    }

    function testSendMessageFailureZeroMessageFee(uint256 messageFee) public {
        vm.assume(messageFee > 0);

        // update the wormhole message fee
        updateWormholeMessageFee(messageFee);

        vm.expectRevert("invalid message fee");
        uniSender.sendMessage{value: 0}(targets, values, datas, address(uniReceiver), bsc_chain_id);
    }

    function testSendMessageFailureMessageFeeTooLarge() public {
        // update the wormhole message fee
        uint256 messageFee = 1e6;
        updateWormholeMessageFee(messageFee);

        // call `sendMessage` with a fee greater than what is set in the wormhole contract
        uint256 invalidFee = 1e18;

        vm.expectRevert("invalid message fee");
        uniSender.sendMessage{value: invalidFee}(targets, values, datas, address(uniReceiver), bsc_chain_id);
    }

    function testReceiveMessageSuccessWithOneAction() public {
        uint64 sequence = 0;
        uint16 emitterChainId = 2;

        bytes memory payload = generateMessagePayload(targets, values, datas, address(uniReceiver), bsc_chain_id);
        bytes memory whMessage = generateSignedVaa(emitterChainId, msgSender, sequence, payload);

        vm.warp(timestamp + 45 minutes);
        uniReceiver.receiveMessage{value: mock.governanceValueOne()}(whMessage);

        // confirm that the mock contract received the governance action
        assertEq(mock.consumedActions(governanceActionOne), true);

        // test that it still works with gaps in the sequence numbers
        sequence = 100;

        // create second governance action signature
        bytes memory encodedGovernanceActionTwo =
            abi.encodeWithSignature("receiveGovernanceMessageTwo(bytes32,uint8)", governanceActionTwo, 2);

        targets[0] = address(mock);
        values[0] = mock.governanceValueTwo();
        datas[0] = encodedGovernanceActionTwo;
        payload = generateMessagePayload(targets, values, datas, address(uniReceiver), bsc_chain_id);
        whMessage = generateSignedVaa(emitterChainId, msgSender, sequence, payload);
        vm.warp(timestamp + 45 minutes);
        uniReceiver.receiveMessage{value: mock.governanceValueTwo()}(whMessage);
    }

    function testReceiveMessageSuccessWithTwoActions() public {
        // create second governance action signature
        bytes memory encodedGovernanceActionTwo =
            abi.encodeWithSignature("receiveGovernanceMessageTwo(bytes32,uint8)", governanceActionTwo, 2);

        // create local instance of targets/values/datas arrays
        address[] memory _targets = new address[](2);
        uint256[] memory _values = new uint256[](2);
        bytes[] memory _datas = new bytes[](2);

        // update the local arrays with the first governance action
        _targets[0] = targets[0];
        _values[0] = values[0];
        _datas[0] = datas[0];

        // update the local arrays with the second governance action
        _targets[1] = address(mock);
        _values[1] = mock.governanceValueTwo();
        _datas[1] = encodedGovernanceActionTwo;

        // other test variables
        uint64 sequence = 1;
        uint16 emitterChainId = 2;
        bytes memory payload = generateMessagePayload(_targets, _values, _datas, address(uniReceiver), bsc_chain_id);
        bytes memory whMessage = generateSignedVaa(emitterChainId, msgSender, sequence, payload);

        vm.warp(timestamp + 45 minutes);
        uint256 multiActionValue = mock.governanceValueOne() + mock.governanceValueTwo();
        uniReceiver.receiveMessage{value: multiActionValue}(whMessage);

        // confirm that the mock contract received the governance action
        assertEq(mock.consumedActions(governanceActionOne), true);
        assertEq(mock.consumedActions(governanceActionTwo), true);
    }

    function testInvalidSubCall() public {
        uint64 sequence = 1;
        uint16 emitterChainId = 2;

        // create bad datas array
        bytes[] memory badDatas = new bytes[](1);
        badDatas[0] = abi.encodeWithSignature("receiveGovernanceMessageOne(bytes32,uint8)", governanceActionOne, 420); // bad action

        bytes memory payload = generateMessagePayload(targets, values, badDatas, address(uniReceiver), bsc_chain_id);
        bytes memory whMessage = generateSignedVaa(emitterChainId, msgSender, sequence, payload);

        vm.warp(timestamp + 45 minutes);

        // note Sometimes forge cannot correctly match the revert string from a call. The
        // expectRevertWithValue performs the same function as vm.expectRevert.
        bytes memory encodedSignature = abi.encodeWithSignature("receiveMessage(bytes)", whMessage);
        expectRevertWithValue(address(uniReceiver), encodedSignature, "Sub-call failed", mock.governanceValueOne());

        // confirm that the mock contract did not receive the governance action
        assertEq(mock.consumedActions(governanceActionOne), false);
    }

    function testIncorrectValueWithOneAction(uint256 _value) public {
        vm.assume(_value != mock.governanceValueOne() && _value < type(uint96).max);

        uint64 sequence = 1;
        uint16 emitterChainId = 2;

        bytes memory payload = generateMessagePayload(targets, values, datas, address(uniReceiver), bsc_chain_id);
        bytes memory whMessage = generateSignedVaa(emitterChainId, msgSender, sequence, payload);

        vm.warp(timestamp + 45 minutes);
        vm.expectRevert("Incorrect value");
        uniReceiver.receiveMessage{value: _value}(whMessage);
    }

    function testIncorrectValueWithTwoActions(uint256 _value) public {
        vm.assume(_value != mock.governanceValueOne() + mock.governanceValueTwo() && _value < type(uint96).max);

        // create second governance action signature
        bytes memory encodedGovernanceActionTwo =
            abi.encodeWithSignature("receiveGovernanceMessageTwo(bytes32,uint8)", governanceActionTwo, 2);

        // create local instance of targets/values/datas arrays
        address[] memory _targets = new address[](2);
        uint256[] memory _values = new uint256[](2);
        bytes[] memory _datas = new bytes[](2);

        // update the local arrays with the first governance action
        _targets[0] = targets[0];
        _values[0] = values[0];
        _datas[0] = datas[0];

        // update the local arrays with the second governance action
        _targets[1] = address(mock);
        _values[1] = mock.governanceValueTwo();
        _datas[1] = encodedGovernanceActionTwo;

        // other test variables
        uint64 sequence = 1;
        uint16 emitterChainId = 2;
        bytes memory payload = generateMessagePayload(_targets, _values, _datas, address(uniReceiver), bsc_chain_id);
        bytes memory whMessage = generateSignedVaa(emitterChainId, msgSender, sequence, payload);

        vm.warp(timestamp + 45 minutes);
        vm.expectRevert("Incorrect value");
        uniReceiver.receiveMessage{value: _value}(whMessage);
    }

    function testInvalidEmitterAddress() public {
        uint64 sequence = 1;

        bytes memory payload = generateMessagePayload(targets, values, datas, address(uniReceiver), bsc_chain_id);
        bytes memory whMessage = generateSignedVaa(ethereum_chain_id, bytes32(uint256(8)), sequence, payload);

        vm.warp(timestamp + 45 minutes);
        vm.expectRevert("Invalid Emitter Address!");
        uniReceiver.receiveMessage(whMessage);
    }

    function testInvalidEmitterChainId() public {
        uint64 sequence = 1;

        bytes memory payload = generateMessagePayload(targets, values, datas, address(uniReceiver), bsc_chain_id);
        bytes memory whMessage = generateSignedVaa(ethereum_chain_id - 1, msgSender, sequence, payload);

        vm.warp(timestamp + 45 minutes);
        vm.expectRevert("Invalid Emitter Chain");
        uniReceiver.receiveMessage(whMessage);
    }

    function testReplay() public {
        uint64 sequence = 1;

        bytes memory payload = generateMessagePayload(targets, values, datas, address(uniReceiver), bsc_chain_id);
        bytes memory whMessage = generateSignedVaa(ethereum_chain_id, msgSender, sequence, payload);

        vm.warp(timestamp + 45 minutes);
        uniReceiver.receiveMessage{value: mock.governanceValueOne()}(whMessage);

        vm.expectRevert("Invalid Sequence number");
        uniReceiver.receiveMessage(whMessage);
    }

    function testInvalidSequence() public {
        uint64 sequence = 2;

        bytes memory payload = generateMessagePayload(targets, values, datas, address(uniReceiver), bsc_chain_id);
        bytes memory whMessage = generateSignedVaa(ethereum_chain_id, msgSender, sequence, payload);

        vm.warp(timestamp + 45 minutes);
        uniReceiver.receiveMessage{value: mock.governanceValueOne()}(whMessage);

        whMessage = generateSignedVaa(ethereum_chain_id, msgSender, sequence - 1, payload);

        vm.expectRevert("Invalid Sequence number");
        uniReceiver.receiveMessage(whMessage);
    }

    function testMessageTimeout() public {
        uint64 sequence = 2;

        bytes memory payload = generateMessagePayload(targets, values, datas, address(uniReceiver), bsc_chain_id);
        bytes memory whMessage = generateSignedVaa(ethereum_chain_id, msgSender, sequence, payload);

        vm.warp(timestamp + 2881 minutes);
        vm.expectRevert("Message no longer valid");
        uniReceiver.receiveMessage(whMessage);
    }

    function testInconsistentPayload() public {
        uint64 sequence = 2;

        bytes memory payload =
            generateMessagePayload(incorrectLengthTargets, values, datas, address(uniReceiver), bsc_chain_id);
        bytes memory whMessage = generateSignedVaa(ethereum_chain_id, msgSender, sequence, payload);

        vm.warp(timestamp + 45 minutes);
        vm.expectRevert("Inconsistent argument lengths");
        uniReceiver.receiveMessage(whMessage);
    }

    function testInvalidReceiverAddress() public {
        uint64 sequence = 2;

        address invalidReceiver = address(uint160(2023));
        bytes memory payload = generateMessagePayload(targets, values, datas, invalidReceiver, bsc_chain_id);
        bytes memory whMessage = generateSignedVaa(ethereum_chain_id, msgSender, sequence, payload);

        vm.warp(timestamp + 45 minutes);
        vm.expectRevert("Message not for this dest");
        uniReceiver.receiveMessage(whMessage);
    }

    function testInvalidReceiverChain() public {
        uint64 sequence = 2;

        bytes memory payload = generateMessagePayload(targets, values, datas, address(uniReceiver), bsc_chain_id - 1);
        bytes memory whMessage = generateSignedVaa(ethereum_chain_id, msgSender, sequence, payload);

        vm.warp(timestamp + 45 minutes);
        vm.expectRevert("Message not for this chain");
        uniReceiver.receiveMessage(whMessage);
    }

    function testFailingSubcall() public {
        uint64 sequence = 2;

        address[] memory failingTargets = new address[](1);
        failingTargets[0] = 0xb4c79daB8f259C7Aee6E5b2Aa729821864227e84;

        bytes memory payload =
            generateMessagePayload(failingTargets, values, datas, address(uniReceiver), bsc_chain_id - 1);
        bytes memory whMessage = generateSignedVaa(ethereum_chain_id, msgSender, sequence, payload);

        vm.warp(timestamp + 45 minutes);
        vm.expectRevert("Sub-call failed");
        uniReceiver.receiveMessage(whMessage);
    }

    // this is a modification of generateMessagePayload() because we need to control _messagePayloadVersion for the following tests.
    function generateMessagePayloadWithVersion(
        bytes32 _messagePayloadVersion,
        address[] memory _targets,
        uint256[] memory _values,
        bytes[] memory _calldatas,
        address _messageReceiver,
        uint16 _receiverChainId
    ) private pure returns (bytes memory) {
        return abi.encode(_messagePayloadVersion, _targets, _values, _calldatas, _messageReceiver, _receiverChainId);
    }

    function testInvalidMessageType() public {
        bytes32 correctMessagePayloadVersion = keccak256(
            abi.encode(
                "UniswapWormholeMessageSenderV1 (bytes32 receivedMessagePayloadVersion, address[] memory targets, uint256[] memory values, bytes[] memory datas, address messageReceiver, uint16 receiverChainId)"
            )
        );
        bytes32 invalidMessagePayloadVersion = keccak256(abi.encode("invalid"));

        // we are using the locally specified generateMessagePayloadWithVersion() here, so first make sure that it works by testing the happy case.
        uint64 sequence = 2;
        bytes memory payload = generateMessagePayloadWithVersion(
            correctMessagePayloadVersion, targets, values, datas, address(uniReceiver), bsc_chain_id
        );
        bytes memory whMessage = generateSignedVaa(ethereum_chain_id, msgSender, sequence, payload);

        vm.warp(timestamp + 45 minutes);
        uniReceiver.receiveMessage{value: mock.governanceValueOne()}(whMessage);

        // now make sure that it fails with a wrong message type
        sequence = 3;
        payload = generateMessagePayloadWithVersion(
            invalidMessagePayloadVersion, targets, values, datas, address(uniReceiver), bsc_chain_id
        );
        whMessage = generateSignedVaa(ethereum_chain_id, msgSender, sequence, payload);

        vm.warp(timestamp + 45 minutes);
        vm.expectRevert("Wrong payload version");
        uniReceiver.receiveMessage(whMessage);
    }

    function testSetOwner(address newOwner) public {
        vm.assume(newOwner != address(0));

        // call `setOwner`
        uniSender.setOwner(newOwner);

        // confirm state changes
        assertEq(uniSender.owner(), newOwner);
    }

    function testSetOwnerFailureZeroAddress() public {
        address newOwner = address(0);

        // expect the `setOwner` call to revert
        vm.expectRevert("newOwner cannot equal address(0)");
        uniSender.setOwner(newOwner);
    }

    function testSetOwnerFailureOwnerOnly() public {
        address newOwner = address(this);

        // prank the caller's address
        vm.prank(makeAddr("notTheOwner"));

        // expect the `setOwner` call to revert
        vm.expectRevert("sender not owner");
        uniSender.setOwner(newOwner);
    }
}
