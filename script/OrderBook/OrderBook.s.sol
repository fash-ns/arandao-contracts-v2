// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {Script, console} from "forge-std/Script.sol";
import {NFTFundRaiseOrderBook} from "../../src/OrderBook/OrderBook.sol";

contract DeployNFTFundRaiseOrderBook is Script {
    // ── Configuration ──────────────────────────────────────────────────────────

    // Replace with actual addresses before deploying.
    address constant INITIAL_OWNER = 0x1111111111111111111111111111111111111111;
    address constant PAYMENT_TOKEN = 0x2222222222222222222222222222222222222222;
    address constant CORE_CONTRACT = 0x3333333333333333333333333333333333333333;
    address constant COLLECTION = 0x4444444444444444444444444444444444444444;

    // ── Entry point ────────────────────────────────────────────────────────────

    function run() external returns (NFTFundRaiseOrderBook orderBook) {
        _validateConfig();

        vm.startBroadcast();

        orderBook = new NFTFundRaiseOrderBook(INITIAL_OWNER, PAYMENT_TOKEN, CORE_CONTRACT, COLLECTION);

        vm.stopBroadcast();

        _logDeployment(orderBook);
    }

    // ── Internal helpers ───────────────────────────────────────────────────────

    function _validateConfig() internal pure {
        require(INITIAL_OWNER != address(0), "DeployOrderBook: zero owner");
        require(PAYMENT_TOKEN != address(0), "DeployOrderBook: zero payment token");
        require(CORE_CONTRACT != address(0), "DeployOrderBook: zero core contract");
        require(COLLECTION != address(0), "DeployOrderBook: zero collection");
    }

    function _logDeployment(NFTFundRaiseOrderBook orderBook) internal view {
        console.log("NFTFundRaiseOrderBook deployed at:", address(orderBook));
        console.log("Owner:           ", orderBook.owner());
        console.log("Core contract:   ", orderBook.coreContractAddress());
        console.log("Collection:      ", orderBook.supportedCollection());
    }
}
