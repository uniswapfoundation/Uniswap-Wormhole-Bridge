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

contract UniswapWormholeMessageReceiver {
    string public name = "Uniswap Wormhole Message Receiver";
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
    uint256 constant MESSAGE_TIME_OUT_SECONDS = 60 * 60;

    /**
     * @param _bridgeAddress Address of Wormhole bridge contract on this chain.
     * @param _messageSender Address of Uniswap Wormhole Message Sender on sending chain.
     */
    constructor(address bridgeAddress, bytes32 _messageSender) {
        wormhole = IWormhole(bridgeAddress);
        messageSender = _messageSender;
    }

    /**
     * @param _whMessage Wormhole message relayed from a source chain.
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
        // this also acts as a replay protect mechanism to ensure that already executed messages don't execute again
        require(lastExecutedSequence < vm.sequence , "Invalid Sequence number");
        // Increase lastExecutedSequence
        lastExecutedSequence = vm.sequence;

        // check if the message is still valid as defined by the validity period
        require(vm.timestamp + MESSAGE_TIME_OUT_SECONDS <= block.timestamp, "Message no longer valid");

        // verify destination
        (address[] memory targets, uint256[] memory values, bytes[] memory datas, address messageReceiver, uint256 receiverChainId) = abi.decode(vm.payload,(address[], uint256[], bytes[], address, uint16));
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
