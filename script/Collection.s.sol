// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import "forge-std/Script.sol";
import {ArcCollection} from "../src/Collection/Collection.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";

contract DeployArcCollection is Script {
    function run() external {
        // Start broadcasting transactions
        vm.startBroadcast();

        // Example owner address (replace manually when deploying to real chain)
        address owner = msg.sender; // or any explicit address

        // DAI address on Polygon Mainnet
        address dai = 0x8f3Cf7ad23Cd3CaDbD9735AFf958023239c6A063;

        // 1. Deploy implementation contract (logic)
        ArcCollection implementation = new ArcCollection();

        // 2. Deploy UUPS proxy and initialize
        ERC1967Proxy proxy = new ERC1967Proxy(
            address(implementation),
            abi.encodeCall(ArcCollection.initialize, (owner, dai))
        );

        // 3. Cast proxy address to ArcCollection type
        ArcCollection collection = ArcCollection(address(proxy));

        console.log("ArcCollection Implementation:", address(implementation));
        console.log("ArcCollection Proxy (main contract):", address(collection));
        console.log("Owner:", collection.owner());

        vm.stopBroadcast();
    }
}