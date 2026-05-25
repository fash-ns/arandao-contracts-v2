// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {Script, console} from "forge-std/Script.sol";
import {NftFundRaiseCollection} from "../../src/Collection/Collection.sol";

contract DeployNftFundRaiseCollection is Script {
    // ── Configuration ──────────────────────────────────────────────────────────

    // Replace with the actual owner address before deploying.
    address constant OWNER = 0x1111111111111111111111111111111111111111;

    // USDT address on Polygon Mainnet.
    address constant USDT = 0xc2132D05D31c914a87C6611C10748AEb04B58e8F;

    // ── Entry point ────────────────────────────────────────────────────────────

    function run() external returns (NftFundRaiseCollection collection) {
        vm.startBroadcast();

        collection = new NftFundRaiseCollection(OWNER, USDT);

        vm.stopBroadcast();

        console.log("NftFundRaiseCollection deployed at:", address(collection));
        console.log("Owner:      ", collection.owner());
        console.log("USDT token: ", address(collection.usdtToken()));
    }
}
