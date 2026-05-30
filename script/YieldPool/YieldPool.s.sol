// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {Script, console} from "forge-std/Script.sol";
import {YieldPool} from "../../src/YieldPool/YieldPool.sol";

// ─────────────────────────────────────────────────────────────────────────────
// Deployment configuration — replace all placeholder addresses before broadcasting
// ─────────────────────────────────────────────────────────────────────────────
//
//  ARC_TOKEN       — ARC ERC-20 token that users stake
//  USDT_TOKEN      — USDT ERC-20 token distributed as platform revenue
//  REWARDER        — Treasury / multisig authorised to call notifyReward
//  LP_ACTIVATOR    — Address authorised to call activateLpMode once (switches pool to LP mode)
//  UNISWAP_ROUTER  — Uniswap V2 Router02 on the target network
//
// ─────────────────────────────────────────────────────────────────────────────

contract DeployYieldPool is Script {
    // ── Configuration ──────────────────────────────────────────────────────────

    address constant ARC_TOKEN      = 0x1111111111111111111111111111111111111111;
    address constant USDT_TOKEN     = 0x2222222222222222222222222222222222222222;
    address constant REWARDER       = 0x3333333333333333333333333333333333333333;
    address constant LP_ACTIVATOR   = 0x4444444444444444444444444444444444444444;
    address constant UNISWAP_ROUTER = 0x5555555555555555555555555555555555555555;

    // ── Entry point ────────────────────────────────────────────────────────────

    function run() external returns (YieldPool pool) {
        _validateConfig();

        vm.startBroadcast();

        pool = new YieldPool(ARC_TOKEN, USDT_TOKEN, REWARDER, LP_ACTIVATOR, UNISWAP_ROUTER);

        vm.stopBroadcast();

        _logDeployment(pool);
    }

    // ── Internal helpers ───────────────────────────────────────────────────────

    function _validateConfig() internal pure {
        require(ARC_TOKEN      != address(0), "ARC_TOKEN not set");
        require(USDT_TOKEN     != address(0), "USDT_TOKEN not set");
        require(REWARDER       != address(0), "REWARDER not set");
        require(LP_ACTIVATOR   != address(0), "LP_ACTIVATOR not set");
        require(UNISWAP_ROUTER != address(0), "UNISWAP_ROUTER not set");
        require(ARC_TOKEN != USDT_TOKEN, "ARC and USDT must differ");
    }

    function _logDeployment(YieldPool pool) internal view {
        console.log("=== YieldPool Deployment ===");
        console.log("YieldPool:         ", address(pool));
        console.log("arcToken:          ", address(pool.arcToken()));
        console.log("usdtToken:         ", address(pool.usdtToken()));
        console.log("rewarder:          ", pool.rewarder());
        console.log("lpActivator:       ", pool.lpActivator());
        console.log("uniswapRouter:     ", address(pool.uniswapRouter()));
        console.log("lpModeActive:      ", pool.lpModeActive());
        console.log("nextStakeId:       ", pool.nextStakeId());
        console.log("nextLpStakeId:     ", pool.nextLpStakeId());
        console.log("============================");
    }
}
