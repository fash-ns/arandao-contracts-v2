// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {Script, console} from "forge-std/Script.sol";
import {MultiAssetVault} from "../../src/Vault/Vault.sol";

contract DeployMultiAssetVault is Script {
    function run() external {

        vm.startBroadcast();

        address dai = 0x6B175474E89094C44Da98b954EedeAC495271d0F;
        address paxg = 0x45804880De22913dAFE09f4980848ECE6EcbAf78;
        address wbtc = 0x2260FAC5E5542a773Aa44fBCfeDf7C193bc2C599;
        address dnm = 0x1111111111111111111111111111111111111111;
        address feedAddr = 0x2222222222222222222222222222222222222222;
        address coreAddr = 0x3333333333333333333333333333333333333333;
        address routerAddr = 0x4444444444444444444444444444444444444444;

        address admin1 = 0x5555555555555555555555555555555555555555;
        address admin2 = 0x6666666666666666666666666666666666666666;
        address admin3 = 0x7777777777777777777777777777777777777777;
        address feeReceiver = 0x8888888888888888888888888888888888888888;

        MultiAssetVault vault = new MultiAssetVault(
            dai,
            paxg,
            wbtc,
            dnm,
            feedAddr,
            coreAddr,
            routerAddr,
            admin1,
            admin2,
            admin3,
            feeReceiver
        );

        console.log("MultiAssetVault deployed at:", address(vault));
        vm.stopBroadcast();
    }
}