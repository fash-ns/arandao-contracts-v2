// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {Script, console} from "forge-std/Script.sol";
import {PriceFeed} from "../../src/Vault/VaultCore/PriceFeed.sol";

contract DeployPriceFeed is Script {
    function run() external returns (address) {
        // Example feed addresses (Sepolia)
        address paxgUsdFeed = 0x0f6914d8e7e1214CDb3A4C6fbf729b75C69DF608; // PAXG / USD
        address wbtcUsdFeed = 0xDE31F8bFBD8c84b5360CFACCa3539B938dd78ae6; // WBTC / USD
        address daiUsdFeed = 0x4746DeC9e833A82EC7C2C1356372CcF2cfcD2F3D; // DAI / USD

        // usually Chainlink feeds return with 8 decimals
        uint8 feedDecimals = 8;

        vm.startBroadcast();

        PriceFeed consumer = new PriceFeed(paxgUsdFeed, wbtcUsdFeed, daiUsdFeed, feedDecimals);

        vm.stopBroadcast();

        console.log("PriceFeed: ", address(consumer));
        return address(consumer);
    }
}
