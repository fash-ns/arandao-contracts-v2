// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import "forge-std/Script.sol";
import "../src/Collection.sol";

contract DeployMyToken is Script {
    function run() external {
        address owner = makeAddr("owner");

        vm.startBroadcast();

        MyToken token = new MyToken(owner);

        console.log("MyToken deployed at:", address(token));
        console.log("Owner:", token.owner());

        vm.stopBroadcast();
    }
}
