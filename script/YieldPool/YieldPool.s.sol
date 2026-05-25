// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {Script, console} from "forge-std/Script.sol";
import {YieldPool} from "../../src/YieldPool/YieldPool.sol";

// ─────────────────────────────────────────────────────────────────────────────
// Deployment configuration — replace these addresses before broadcasting
// ─────────────────────────────────────────────────────────────────────────────
//
//  arcToken  — ARC ERC-20 token that users stake
//  usdtToken — USDT ERC-20 token distributed as platform revenue
//  rewarder  — Treasury / multisig authorised to call notifyReward
//
// ─────────────────────────────────────────────────────────────────────────────

contract DeployYieldPool is Script {
    // ── Configuration ──────────────────────────────────────────────────────────

    address constant ARC_TOKEN = 0x1111111111111111111111111111111111111111;
    address constant USDT_TOKEN = 0x2222222222222222222222222222222222222222;
    address constant REWARDER = 0x3333333333333333333333333333333333333333;

    // ── Entry point ────────────────────────────────────────────────────────────

    function run() external returns (YieldPool pool) {
        _validateConfig();

        vm.startBroadcast();

        pool = new YieldPool(ARC_TOKEN, USDT_TOKEN, REWARDER);

        vm.stopBroadcast();

        _logDeployment(pool);
    }

    // ── Internal helpers ───────────────────────────────────────────────────────

    function _validateConfig() internal pure {
        require(ARC_TOKEN != address(0), "ARC_TOKEN not set");
        require(USDT_TOKEN != address(0), "USDT_TOKEN not set");
        require(REWARDER != address(0), "REWARDER not set");
        require(ARC_TOKEN != USDT_TOKEN, "ARC and USDT must be different tokens");
    }

    function _logDeployment(YieldPool pool) internal view {
        console.log("=== YieldPool Deployment ===");
        console.log("YieldPool:   ", address(pool));
        console.log("arcToken:    ", address(pool.arcToken()));
        console.log("usdtToken:   ", address(pool.usdtToken()));
        console.log("rewarder:    ", pool.rewarder());
        console.log("nextStakeId: ", pool.nextStakeId());
        console.log("totalStaked: ", pool.totalStaked());
        console.log("============================");
    }
}
