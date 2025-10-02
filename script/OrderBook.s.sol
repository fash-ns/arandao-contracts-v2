// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import {Script, console} from "forge-std/Script.sol";
import {NFTOrderBook} from "../src/OrderBook.sol";

contract DeployNFTOrderBook is Script {
    function run() external {
        vm.startBroadcast();

        address initialOwner = address(1);
        address usdtToken = address(2);
        address bvRecipient = address(3);
        address feeRecipient = address(4);
        uint256 denom = 167;
        uint256 sellerNum = 50;
        uint256 bvNum = 100;
        uint256 minimumPrice = 1e6;

        NFTOrderBook orderBook =
            new NFTOrderBook(initialOwner, usdtToken, bvRecipient, feeRecipient, denom, sellerNum, bvNum, minimumPrice);

        console.log("NFTOrderBook deployed at:", address(orderBook));
        vm.stopBroadcast();
    }
}
