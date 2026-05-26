// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {Script, console} from "forge-std/Script.sol";
import {Dex} from "../../src/Dex/Dex.sol";

contract DeployDex is Script {
    // ── Configuration ──────────────────────────────────────────────────────────

    // Replace with the actual addresses before deploying.
    address constant ARC_TOKEN = 0x2222222222222222222222222222222222222222;
    address constant USDT_TOKEN = 0x3333333333333333333333333333333333333333;
    address constant FEE_RECEIVER = 0x4444444444444444444444444444444444444444;
    address constant VAULT = 0x5555555555555555555555555555555555555555;

    // ── Entry point ────────────────────────────────────────────────────────────

    function run() external returns (Dex dex) {
        _validateConfig();

        vm.startBroadcast();

        dex = new Dex(ARC_TOKEN, USDT_TOKEN, FEE_RECEIVER, VAULT);

        vm.stopBroadcast();

        _logDeployment(dex);
    }

    function _validateConfig() internal pure {
        require(ARC_TOKEN != address(0), "DeployDex: zero ARC token");
        require(USDT_TOKEN != address(0), "DeployDex: zero USDT token");
        require(FEE_RECEIVER != address(0), "DeployDex: zero fee receiver");
        require(VAULT != address(0), "DeployDex: zero vault");
        require(ARC_TOKEN != USDT_TOKEN, "DeployDex: same token addresses");
    }

    function _logDeployment(Dex dex) internal view {
        console.log("Dex deployed at:  ", address(dex));
        console.log("ARC token:        ", dex.arcToken());
        console.log("USDT token:       ", dex.usdtToken());
        console.log("Fee receiver:     ", dex.feeReceiver());
    }
}
