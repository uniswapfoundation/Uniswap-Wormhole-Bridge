pragma solidity ^0.8.9;

interface IWormhole {
    function publishMessage(uint32 nonce, bytes memory payload, uint8 consistencyLevel) external payable returns (uint64 sequence);

    function messageFee() external view returns (uint256);
}

contract UniswapWormholeMessageSender {
    string public name = "Uniswap Wormhole Message Sender";

    address public owner;

    uint32 public nonce;
    uint8 consistencyLevel = 1;

    event  MessageSent(bytes payload, address indexed messageReceiver);

    IWormhole private immutable wormhole;

    constructor(address bridgeAddress) {
        wormhole = IWormhole(bridgeAddress);
    }

    function sendMessage(address[] memory targets, uint256[] memory values, bytes[] memory datas, address messageReceiver, uint16 receiverChainId) external onlyOwner payable {
        bytes memory payload = abi.encode(targets,values,datas,messageReceiver,receiverChainId);
        
        wormhole.publishMessage{value: wormhole.messageFee()}(nonce, payload, consistencyLevel);
        nonce = nonce + 1;

        emit MessageSent(payload, messageReceiver);
    }
}
