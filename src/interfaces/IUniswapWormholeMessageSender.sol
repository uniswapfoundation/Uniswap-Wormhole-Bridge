// contracts/Structs.sol
// SPDX-License-Identifier: Apache 2

pragma solidity ^0.8.9;

interface IUniswapWormholeMessageSender {
    function sendMessage(
        address[] memory targets,
        uint256[] memory values,
        bytes[] memory datas,
        address messageReceiver,
        uint16 receiverChainId
    ) external payable;
    function owner() external returns (address);
    function setOwner(address newOwner) external;
}
