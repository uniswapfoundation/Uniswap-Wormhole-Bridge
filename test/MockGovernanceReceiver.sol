// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

contract MockGovernanceReceiver {
    address trustedCaller;

    // governance action values
    uint256 public constant governanceValueOne = 1e13;
    uint256 public constant governanceValueTwo = 1e17;

    mapping(bytes32 => bool) public consumedActions;

    constructor(address _trustedCaller) {
        require(_trustedCaller != address(0), "invalid caller address");

        trustedCaller = _trustedCaller;
    }

    function receiveGovernanceMessageOne(bytes32 governanceAction, uint8 governanceType) public payable {
        require(governanceType == 1, "invalid governance type");
        require(msg.sender == trustedCaller, "unknown caller");
        require(!consumedActions[governanceAction], "action already consumed");
        require(msg.value == governanceValueOne, "not enough value");

        consumedActions[governanceAction] = true;
    }

    function receiveGovernanceMessageTwo(bytes32 governanceAction, uint8 governanceType) public payable {
        require(governanceType == 2, "invalid governance type");
        require(msg.sender == trustedCaller, "unknown caller");
        require(!consumedActions[governanceAction], "action already consumed");
        require(msg.value == governanceValueTwo, "not enough value");

        consumedActions[governanceAction] = true;
    }
}
