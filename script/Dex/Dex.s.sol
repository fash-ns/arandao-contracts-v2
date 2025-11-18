// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {Script, console} from "forge-std/Script.sol";
import {Dex} from "../../src/Dex/Dex.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";

contract DeployDex is Script {
    function run() external {
        vm.startBroadcast();

        address initialOwner = 0x1111111111111111111111111111111111111111;
        address dnmToken = 0x2222222222222222222222222222222222222222;
        address daiToken = 0x3333333333333333333333333333333333333333;
        address feeReceiver = 0x4444444444444444444444444444444444444444;
        address vault = 0x5555555555555555555555555555555555555555;

        // Deploy implementation contract
        Dex dexImplementation = new Dex();

        // Prepare encoded initializer data
        bytes memory initData = abi.encodeCall(Dex.initialize, (initialOwner, dnmToken, daiToken, feeReceiver, vault));

        // Deploy proxy pointing to implementation
        ERC1967Proxy proxy = new ERC1967Proxy(address(dexImplementation), initData);

        // Dex proxy instance
        Dex dex = Dex(address(proxy));

        console.log("Dex Proxy deployed at:", address(dex));
        console.log("Dex Implementation deployed at:", address(dexImplementation));
        console.log("Owner:", dex.owner());

        vm.stopBroadcast();
    }
}
