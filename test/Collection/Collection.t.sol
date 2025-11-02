// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import {Test} from "forge-std/Test.sol";
import {ArcCollection} from "../../src/Collection/Collection.sol";
import {MockToken} from "../mocks/MockToken.sol";

contract ArcCollectionTest is Test {
    ArcCollection internal collection;
    MockToken internal dai;

    uint256[] public ids;
    string[] public uris;

    address internal owner = makeAddr("owner");
    address internal alice = makeAddr("alice");
    address internal bob = makeAddr("bob");

    function setUp() public {
        dai = new MockToken(address(3), 1_000_000 ether);
        collection = new ArcCollection(owner, address(dai));
    }

    // ----------------------------
    // Deployment
    // ----------------------------
    function testDeployment() public view {
        assertEq(address(collection.daiToken()), address(dai));
        assertEq(collection.owner(), owner);
        assertEq(collection.claimRound(), 0);
    }

    // ----------------------------
    // Ownership Transfer
    // ----------------------------
    function testTransferOwnershipOnce() public {
        address newOwner = makeAddr("newOwner");
        vm.prank(owner);
        collection.transferOwnership(newOwner);

        assertTrue(collection.ownershipFlag());
        assertEq(collection.owner(), newOwner);

        vm.prank(newOwner);
        vm.expectRevert("Ownership has already been transferred");
        collection.transferOwnership(owner);
    }

    // ----------------------------
    // URI Management
    // ----------------------------
    function testSetURI() public {
        string memory newUri = "ipfs://new/";
        vm.prank(owner);
        collection.setURI(0, newUri);

        string memory fetchedUri = collection.uri(0);
        assertEq(fetchedUri, newUri);
    }

    // ----------------------------
    // Transfer Allowlist
    // ----------------------------
    function testAddAndRemoveTransferAllowedAddress() public {
        vm.startPrank(owner);

        vm.expectRevert("Invalid address");
        collection.addTransferAllowedAddress(address(0));

        collection.addTransferAllowedAddress(alice);
        vm.expectRevert("Already authorized");
        collection.addTransferAllowedAddress(alice);

        collection.removeTransferAllowedAddress(alice);
        vm.expectRevert("Not authorized");
        collection.removeTransferAllowedAddress(alice);

        vm.stopPrank();
    }

    function testTransferRestriction() public {
        vm.startPrank(owner);
        collection.addTransferAllowedAddress(alice);
        collection.addTransferAllowedAddress(address(this)); // allow test contract
        vm.stopPrank();

        // mint token via internal helper through prank
        vm.prank(owner);
        collection.addClaimRound(uint128(block.timestamp + 100), 1 ether);

        vm.warp(block.timestamp + 101);
        dai.mint(alice, 1 ether);
        vm.startPrank(alice);
        dai.approve(address(collection), 1 ether);

        // should fail because not in claim period for tokenId 0 yet (no prior balance)
        vm.expectRevert("must own token to claim");
        collection.claimTokens(0, 1);
        vm.stopPrank();
    }

    // ----------------------------
    // Claim Rounds
    // ----------------------------
    function testAddClaimRoundAndDisablePrevious() public {
        vm.startPrank(owner);
        collection.addClaimRound(uint128(block.timestamp + 1000), 1 ether);
        assertEq(collection.claimRound(), 1);

        // Add second round disables the first
        collection.addClaimRound(uint128(block.timestamp + 2000), 2 ether);
        assertEq(collection.claimRound(), 2);

        (,,,, bool firstEnabled) = collection.claimRounds(1);
        assertFalse(firstEnabled);
        vm.stopPrank();
    }

    // ----------------------------
    // Claim Logic
    // ----------------------------
    function testClaimTokensFlow() public {
        // 1. Setup initial mint for alice (owner mint)
        vm.startPrank(owner);
        collection.tokenMint(alice, 0, 1, "ipfs://uri0"); // simulate pre-existing balance
        collection.tokenMint(alice, 1, 1, "ipfs://uri1");
        collection.addClaimRound(uint128(block.timestamp + 100), 1 ether);
        vm.stopPrank();

        // 2. Fund and approve DAI for alice
        dai.mint(alice, 10 ether);
        vm.startPrank(alice);
        dai.approve(address(collection), 10 ether);

        // 3. Warp into active claim round
        vm.warp(block.timestamp + 101);

        // 4. Perform claim
        collection.claimTokens(0, 1);

        assertEq(collection.balanceOf(alice, 0), 2);
        assertEq(collection.mintedInRoundFor(1, 0), 1);
        assertEq(collection.alreadyClaimedInRound(1, 0, alice), 1);

        string memory expectedUri = collection.uri(0);
        assertEq(expectedUri, "ipfs://uri0");

        string memory expectedUri1 = collection.uri(1);
        assertEq(expectedUri1, "ipfs://uri1");

        vm.stopPrank();
    }

    // ----------------------------
    // Owner Claim of Unclaimed Tokens
    // ----------------------------
    function testOwnerClaimAfterDeadline() public {
        vm.startPrank(owner);
        collection.tokenMint(alice, 0, 1, "ipfs://uri0");
        collection.addClaimRound(uint128(block.timestamp + 100), 1 ether);
        vm.stopPrank();

        // Warp past end time (start + 30 days)
        vm.warp(block.timestamp + 100 + 30 days + 1);

        vm.prank(owner);
        collection.claimByOwner(1, 0); // claim remaining for tokenId=0
    }

    // ----------------------------
    // Batch Owner Claim
    // ----------------------------
    function testBatchOwnerClaim() public {
        vm.startPrank(owner);
        collection.tokenMint(alice, 0, 1, "ipfs://uri0");
        collection.tokenMint(alice, 1, 1, "ipfs://uri1");
        collection.addClaimRound(uint128(block.timestamp + 100), 1 ether);
        vm.stopPrank();

        // Warp past end time
        vm.warp(block.timestamp + 100 + 30 days + 1);

        ids.push(0);
        ids.push(1);

        vm.prank(owner);
        collection.batchOwnerClaim(1, ids);
    }
}
