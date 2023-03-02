pragma solidity ^0.8.9;
import "./Structs.sol";

interface IWormhole {
    function parseAndVerifyVM(bytes calldata encodedVM) external view returns (Structs.VM memory vm, bool valid, string memory reason);
}

contract UniswapWormholeMessageReceiver {
    string public name = "Uniswap Wormhole Message Receiver";

    address public owner;
    bytes32 public messageSender;

    IWormhole private immutable wormhole;
    uint16 immutable ETHEREUM_CHAIN_ID = 2;
    uint16 immutable BSC_CHAIN_ID = 4;

    // keeps track of the sequence number of the last executed wormhole message
    uint64 lastExecutedSequence;

    // period for which a wormhole message is considered active before it times out and is no longer accepted by the contract
    uint256 msgValidityPeriod;

    constructor(address bridgeAddress, bytes32 _messageSender, uint256 _msgValidityPeriod) {
        wormhole = IWormhole(bridgeAddress);
        messageSender = _messageSender;
        owner = msg.sender;

        // msgValidityPeriod needs to be set to a value greater than the finality time on ethereum otherwise the message expires even before it can be signed
        msgValidityPeriod = _msgValidityPeriod;
    }

    modifier onlyOwner() {
        require(msg.sender == owner, "sender not owner");
        _;
    }

    function receiveMessage(bytes memory whMessage) public {
        (Structs.VM memory vm, bool valid, string memory reason) = wormhole.parseAndVerifyVM(whMessage);

        // validate
        require(valid, reason);
        
        // Ensure the emitterAddress of this VAA is the Uniswap message sender
        require(messageSender == vm.emitterAddress, "Invalid Emitter Address!");

        // Ensure the emitterChainId is Ethereum to prevent impersonation
        require(vm.emitterChainId == ETHEREUM_CHAIN_ID, "Invalid Emmiter Chain");

        // Ensure that the sequence field in the VAA is strictly monotonically increasing
        // this also acts as a replay protect mechanism to ensure that already executed messages don't execute again
        require(lastExecutedSequence < vm.sequence , "Invalid Sequence number");
        // increment lastExecutedSequence
        lastExecutedSequence += 1;

        // check if the message is still valid as defined by the validity period
        require(vm.timestamp + msgValidityPeriod <= block.timestamp, "Message no longer valid");

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

    function setOwner(address newOwner) external onlyOwner {
        owner = newOwner;
    }
}
