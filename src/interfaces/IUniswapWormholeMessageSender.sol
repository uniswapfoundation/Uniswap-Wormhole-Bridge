// contracts/Structs.sol
// SPDX-License-Identifier: Apache 2

pragma solidity ^0.8.9;

interface IUniswapWormholeMessageSender {
    function sendMessage(
        address[] memory targets,
        uint256[] memory values,
        bytes[] memory datas,
        string[] memory signatures,
        address messageReceiver,
        uint16 receiverChainId
    ) external payable;
    function owner() external returns (address);
    function pendingOwner() external returns (address);
    function submitOwnershipTransferRequest(address newOwner) external;
    function cancelOwnershipTransferRequest() external;
    function confirmOwnershipTransferRequest() external;
}
