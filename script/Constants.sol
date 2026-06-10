// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.12;

library Constants {
    function smokeCheck() internal pure {
        require(
            WORMHOLE_CORE != address(0x00),
            "Constants.WORMHOLE_CORE is not set."
        );
        require(
            MESSAGE_SENDER != address(0x00),
            "Constants.MESSAGE_SENDER is not set."
        );
        require(
            WORMHOLE_CHAIN_ID != 0,
            "Constants.WORMHOLE_CHAIN_ID is not set."
        );
        require(
            WORMHOLE_ETHEREUM_CHAIN_ID == 2,
            "Constants.WORMHOLE_ETHEREUM_CHAIN_ID is incorrect."
        );
    }

    address internal constant WORMHOLE_CORE = address(0x00);
    address internal constant MESSAGE_SENDER = address(0x00);
    uint16 internal constant WORMHOLE_CHAIN_ID = 0;
    uint16 internal constant WORMHOLE_ETHEREUM_CHAIN_ID = 2;
}