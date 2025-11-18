// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import {Script, console} from "forge-std/Script.sol";
import {NFTOrderBook} from "../../src/OrderBook/OrderBook.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";

contract DeployNFTOrderBook is Script {
    function run() external {
        vm.startBroadcast();

        // --- Step 1: Deploy the implementation contract ---
        NFTOrderBook implementation = new NFTOrderBook();
        console.log("NFTOrderBook Implementation deployed at:", address(implementation));

        // --- Step 2: Prepare initializer calldata ---
        address initialOwner = makeAddr("owner");
        address paymentToken = 0x3;
        address coreContractAddress = 0x4; // Core contract address
        address collectionAddr = 0x5; // Supported ERC1155 collection address

        // ABI encode initialize function call
        bytes memory data = abi.encodeWithSelector(
            NFTOrderBook.initialize.selector, initialOwner, paymentToken, coreContractAddress, collectionAddr
        );

        // --- Step 3: Deploy ERC1967 Proxy pointing to implementation ---
        ERC1967Proxy proxy = new ERC1967Proxy(address(implementation), data);
        console.log("NFTOrderBook Proxy deployed at:", address(proxy));

        vm.stopBroadcast();
    }
}
