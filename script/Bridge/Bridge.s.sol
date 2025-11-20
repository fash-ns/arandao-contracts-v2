// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

import "forge-std/Script.sol";
import "forge-std/Test.sol";
import {AranDAOBridge} from "../../src/Bridge/Bridge.sol";
import {AranDAOBridgeV2} from "../../src/Bridge/BridgeV2.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {UUPSUpgradeable} from "@openzeppelin/contracts/proxy/utils/UUPSUpgradeable.sol";

contract DeployAranDAOBridgeProxyTest is Script, Test {
    function run() external {
        // Test addresses
        address owner = makeAddr("owner");
        address oldUvm = makeAddr("oldUvm");
        address oldDnm = makeAddr("oldDnm");
        address oldWrapper = makeAddr("oldWrapper");
        address oldStake = makeAddr("oldStake");
        address arc = makeAddr("arc");

        vm.startBroadcast(owner);

        //  Deploy V1 Implementation
        AranDAOBridge implV1 = new AranDAOBridge();

        bytes memory initData = abi.encodeWithSignature(
            "initialize(address,address,address,address,address,address)",
            owner,
            oldUvm,
            oldDnm,
            oldWrapper,
            oldStake,
            arc
        );

        ERC1967Proxy proxy = new ERC1967Proxy(address(implV1), initData);

        AranDAOBridge bridge = AranDAOBridge(address(proxy));

        console.log("V1 Proxy deployed at:", address(bridge));
        console.log("Owner:", owner);

        //  Deploy V2 Implementation
        AranDAOBridgeV2 implV2 = new AranDAOBridgeV2();
        console.log("V2 Implementation deployed at:", address(implV2));

        bridge.upgradeToAndCall(address(implV2), "");
        console.log("Proxy upgraded to V2 at implementation:", address(implV2));

        // Call new functions from V2
        AranDAOBridgeV2 bridgeV2 = AranDAOBridgeV2(address(bridge));

        bridgeV2.version();
        bridgeV2.bridgeDnm();

        vm.stopBroadcast();
    }
}
