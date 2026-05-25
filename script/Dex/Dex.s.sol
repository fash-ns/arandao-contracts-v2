// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {Script, console} from "forge-std/Script.sol";
import {Dex} from "../../src/Dex/Dex.sol";

contract DeployDex is Script {
    // ── Configuration ──────────────────────────────────────────────────────────

    // Replace with the actual addresses before deploying.
    address constant DNM_TOKEN = 0x2222222222222222222222222222222222222222;
    address constant DAI_TOKEN = 0x3333333333333333333333333333333333333333;
    address constant FEE_RECEIVER = 0x4444444444444444444444444444444444444444;
    address constant VAULT = 0x5555555555555555555555555555555555555555;

    // ── Entry point ────────────────────────────────────────────────────────────

    function run() external returns (Dex dex) {
        _validateConfig();

        vm.startBroadcast();

        dex = new Dex(DNM_TOKEN, DAI_TOKEN, FEE_RECEIVER, VAULT);

        vm.stopBroadcast();

        _logDeployment(dex);
    }

    function _validateConfig() internal pure {
        require(DNM_TOKEN != address(0), "DeployDex: zero DNM token");
        require(DAI_TOKEN != address(0), "DeployDex: zero DAI token");
        require(FEE_RECEIVER != address(0), "DeployDex: zero fee receiver");
        require(VAULT != address(0), "DeployDex: zero vault");
        require(DNM_TOKEN != DAI_TOKEN, "DeployDex: same token addresses");
    }

    function _logDeployment(Dex dex) internal view {
        console.log("Dex deployed at:  ", address(dex));
        console.log("DNM token:        ", dex.dnmToken());
        console.log("DAI token:        ", dex.daiToken());
        console.log("Fee receiver:     ", dex.feeReceiver());
    }
}
