// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {Script, console} from "forge-std/Script.sol";
import {Dex} from "../../src/Dex/Dex.sol";
import {DexStorage} from "../../src/Dex/DexCore/DexStorage.sol";

contract DeployDex is Script {
    function run() external {

        vm.startBroadcast();

        address initialOwner = 0x1111111111111111111111111111111111111111;
        address dnmToken     = 0x2222222222222222222222222222222222222222;
        address daiToken     = 0x3333333333333333333333333333333333333333;
        address feeReceiver  = 0x4444444444444444444444444444444444444444;
        address vault        = 0x5555555555555555555555555555555555555555;

        DexStorage.FeeTier[] memory tiers = new DexStorage.FeeTier[](2);

        // Example: tier 1: up to 1000 DNM => 0.3% fee
        tiers[0] = DexStorage.FeeTier({
            volumeFloor: 1000 ether,
            feeBps: 30
        });

        // Example: tier 2: up to 10,000 DNM => 0.1% fee
        tiers[1] = DexStorage.FeeTier({
            volumeFloor: 10000 ether,
            feeBps: 10 // 0.1%
        });

        Dex dex = new Dex(
            initialOwner,
            dnmToken,
            daiToken,
            feeReceiver,
            vault,
            tiers
        );

        console.log("Dex deployed at:", address(dex));

        vm.stopBroadcast();
    }
}