// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {Script, console} from "forge-std/Script.sol";
import {MultiAssetVault} from "../../src/Vault/Vault.sol";
import {VaultStorage} from "../../src/Vault/VaultCore/VaultStorage.sol";

contract DeployMultiAssetVault is Script {
    VaultStorage.InitParams params;

    function run() external {
        vm.startBroadcast();

        address dai = 0x8f3Cf7ad23Cd3CaDbD9735AFf958023239c6A063;
        address usdc = 0x2791Bca1f2de4661ED88A30C99A7a9449Aa84174;
        address wbtc = 0x1BFD67037B42Cf73acF2047067bd4F2C47D9BfD6;
        address paxg = 0x553d3D295e0f695B9228246232eDF400ed3560B5;
        address dnm = 0x1111111111111111111111111111111111111111;

        address uniswapRouter = 0xE592427A0AEce92De3Edee1F18E0157C05861564;
        address uniswapQuoter = 0xb27308f9F90D607463bb33eA1BeBb41C27CE5AB6;

        address feedAddr = 0x2222222222222222222222222222222222222222;
        address coreAddr = 0x3333333333333333333333333333333333333333;

        params = VaultStorage.InitParams({
            dai: dai,
            paxg: paxg,
            wbtc: wbtc,
            usdc: usdc,
            dnm: dnm,
            priceFeed: feedAddr,
            coreContract: coreAddr,
            uniswapRouter: uniswapRouter,
            uniswapQuoter: uniswapQuoter,
            admin1: address(1),
            admin2: address(2),
            admin3: address(3),
            feeReceiver: address(4)
        });

        MultiAssetVault vault = new MultiAssetVault(params);

        console.log("MultiAssetVault deployed at:", address(vault));
        vm.stopBroadcast();
    }
}
