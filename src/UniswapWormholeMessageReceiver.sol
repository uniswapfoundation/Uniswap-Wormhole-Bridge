/**
 * Copyright Uniswap Foundation 2023
 *
 * This code is based on code deployed here: https://bscscan.com/address/0x3ee84fFaC05E05907E6AC89921f000aE966De001#code
 *
 * Licensed under the Apache License, Version 2.0 (the "License"); you may not use this file except in compliance with
 * the License. You may obtain a copy of the License at
 *
 * http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software distributed under the License is distributed on
 * an "AS IS" BASIS, WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied. See the License for the
 * specific language governing permissions and limitations under the License.
 *
 * SPDX-License-Identifier: Apache-2.0
 */
pragma solidity ^0.8.9;
import "./Structs.sol";

interface IWormhole {
    function parseAndVerifyVM(bytes calldata encodedVM) external view returns (Structs.VM memory vm, bool valid, string memory reason);
}

/**
@title  Uniswap Wormhole Message Receiver
@dev    this contract receives and executes Uniswap governance proposals that were sent from the UniswapWormholeMessageSender
        contract on Ethereum via Wormhole.
        It enforces that proposals are executed in order, but it does not guarantee that all proposals are executed.
        i.e. The message sequence number of proposals must be strictly monotonically increasing, but need not be consecutive
        The maximum number of proposals that can be received is therefore UINT64_MAX.
        For example, if there are proposals 1,2 and 3, then the following are valid executions (not exhaustive):
            1,2,3
            1,3
        But the following are impossible (not exhaustive):
            1,3,2
*/
contract UniswapWormholeMessageReceiver {
    string public name = "Uniswap Wormhole Message Receiver";

    // address of the UniswapWormholeMessageSender contract on ethereum in Wormhole format, i.e. 12 zero bytes followed by a 20-byte Ethereum address
    bytes32 public messageSender;

    IWormhole private immutable wormhole;
    uint16 immutable ETHEREUM_CHAIN_ID = 2;
    uint16 immutable BSC_CHAIN_ID = 4;

    // keeps track of the sequence number of the last executed wormhole message
    uint64 lastExecutedSequence;

    // Message timeout in seconds: Time out needs to account for:
    //  Finality time on source chain.
    //  Time for Wormhole validators to sign and make VAA available to relayers.
    //  Time to relay VAA to the target chain.
    //  Congestion on target chain leading to delayed inclusion of transaction in target chain.
    // Have the value set to one hour.
    // Note that there is no way to alter this hard coded value. Including such a feature
    // would require some governance structure and some minumum and maximum values.
    uint256 constant MESSAGE_TIME_OUT_SECONDS = 1 hours;

    /**
     * @param bridgeAddress Address of Wormhole bridge contract on this chain.
     * @param _messageSender // address of the UniswapWormholeMessageSender contract on ethereum in Wormhole format, i.e. 12 zero bytes followed by a 20-byte Ethereum address
     */
    constructor(address bridgeAddress, bytes32 _messageSender) {
        wormhole = IWormhole(bridgeAddress);
        messageSender = _messageSender;
    }

    /**
     * @param whMessage Wormhole message relayed from a source chain.
     */
    function receiveMessage(bytes memory whMessage) public {
        (Structs.VM memory vm, bool valid, string memory reason) = wormhole.parseAndVerifyVM(whMessage);

        // validate
        require(valid, reason);

        // Ensure the emitterAddress of this VAA is the Uniswap message sender
        require(messageSender == vm.emitterAddress, "Invalid Emitter Address!");

        // Ensure the emitterChainId is Ethereum to prevent impersonation
        require(vm.emitterChainId == ETHEREUM_CHAIN_ID, "Invalid Emitter Chain");

        // Ensure that the sequence field in the VAA is strictly monotonically increasing
        // this also acts as a replay protection mechanism to ensure that already executed messages don't execute again
        require(lastExecutedSequence < vm.sequence , "Invalid Sequence number");
        // Increase lastExecutedSequence
        lastExecutedSequence = vm.sequence;

        // check if the message is still valid as defined by the validity period
        require(vm.timestamp + MESSAGE_TIME_OUT_SECONDS >= block.timestamp, "Message no longer valid");

        // verify destination
        (address[] memory targets, uint256[] memory values, bytes[] memory datas, address messageReceiver, uint16 receiverChainId) = abi.decode(vm.payload,(address[], uint256[], bytes[], address, uint16));
        require (messageReceiver == address(this), "Message not for this dest");
        require (receiverChainId == BSC_CHAIN_ID, "Message not for this chain");

        // execute message
        require(targets.length == datas.length && targets.length == values.length, 'Inconsistent argument lengths');
        for (uint256 i = 0; i < targets.length; i++) {
            (bool success, ) = targets[i].call{value: values[i]}(datas[i]);
            require(success, 'Sub-call failed');
        }
    }
}
