// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {Test} from "forge-std/Test.sol";
import {ArcCollection} from "../../src/Collection/Collection.sol";
import {MockToken} from "../mocks/MockToken.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";

contract ArcCollectionExtraTest is Test {
    ArcCollection internal collection;
    MockToken internal dai;

    address internal owner = makeAddr("owner");
    address internal alice = makeAddr("alice");
    address internal bob = makeAddr("bob");
    address internal attacker = makeAddr("attacker");

    uint256[] internal defaultIds;
    uint256[] internal defaultAmounts;
    string[] internal defaultUris;

    function setUp() public {
        dai = new MockToken(address(3), 1_000_000 ether);

        // Deploy implementation
        ArcCollection implementation = new ArcCollection();

        // Deploy UUPS proxy pointing to implementation
        ERC1967Proxy proxy =
            new ERC1967Proxy(address(implementation), abi.encodeCall(ArcCollection.initialize, (owner, address(dai))));

        // Bind proxy address to ArcCollection interface
        collection = ArcCollection(address(proxy));

        defaultIds.push(0);
        defaultIds.push(1);

        defaultAmounts.push(1);
        defaultAmounts.push(1);

        defaultUris.push("ipfs://uri0");
        defaultUris.push("ipfs://uri1");
    }

    // ----------------------------
    // Ownership / Access control
    // ----------------------------
    function testCannotTransferOwnershipByNonOwner() public {
        vm.prank(attacker);
        vm.expectRevert();
        collection.transferOwnership(makeAddr("someone"));
    }

    function testTransferOwnershipOnceRevertsSecondTime() public {
        address newOwner = makeAddr("newOwner");
        vm.prank(owner);
        collection.transferOwnership(newOwner);

        // newOwner cannot transfer again because ownershipFlag set
        vm.prank(newOwner);
        vm.expectRevert("Ownership has already been transferred");
        collection.transferOwnership(owner);
    }

    // ----------------------------
    // Initial Mint only once
    // ----------------------------
    function testOwnerCannotMintTwice_initialMintDisabledAfterFirst() public {
        // first mint by owner should succeed
        vm.prank(owner);
        collection.batchTokenMint(alice, defaultIds, defaultAmounts);

        // second attempt should revert because isInitialMintEnable -> false
        vm.prank(owner);
        vm.expectRevert("Mint is not enable");
        collection.batchTokenMint(bob, defaultIds, defaultAmounts);
    }

    // ----------------------------
    // Claim round / validation edge cases
    // ----------------------------
    function testClaimBeforeAnyRoundReverts() public {
        // alice tries to claim when no rounds exist
        vm.prank(alice);
        vm.expectRevert("no active round");
        collection.claimTokens(0, 1);
    }

    function testClaimWithZeroAmountReverts() public {
        // Setup initial mint so alice holds token 0
        vm.prank(owner);
        collection.batchTokenMint(alice, defaultIds, defaultAmounts);

        // create round
        vm.prank(owner);
        collection.addClaimRound(uint128(block.timestamp + 10), 1 ether);

        // warp and attempt to claim zero
        vm.warp(block.timestamp + 11);

        vm.prank(alice);
        vm.expectRevert("invalid amount");
        collection.claimTokens(0, 0);
    }

    function testClaimRevertsIfNoDAIApprovalOrInsufficient() public {
        // owner mints so alice has token
        vm.prank(owner);
        collection.batchTokenMint(alice, defaultIds, defaultAmounts);

        // create round
        vm.prank(owner);
        collection.addClaimRound(uint128(block.timestamp + 10), 1 ether);

        // warp into round
        vm.warp(block.timestamp + 11);

        // alice does NOT approve or does not have DAI -> transferFrom will revert
        // either because allowance is zero or balance is zero. Use expectRevert without message.
        vm.prank(alice);
        vm.expectRevert();
        collection.claimTokens(0, 1);
    }

    function testClaimTransfersDAIToOwner() public {
        // 1. owner mints tokens to alice
        vm.startPrank(owner);
        collection.batchTokenMint(alice, defaultIds, defaultAmounts);
        collection.addClaimRound(uint128(block.timestamp + 10), 1 ether);
        vm.stopPrank();

        // 2. fund alice and approve
        dai.mint(alice, 5 ether);
        vm.prank(alice);
        dai.approve(address(collection), 5 ether);

        // 3. warp into round
        vm.warp(block.timestamp + 11);

        // record owner balance before
        uint256 before = dai.balanceOf(owner);

        vm.prank(alice);
        collection.claimTokens(0, 1);

        // owner must have received 1 ether
        assertEq(dai.balanceOf(owner), before + 1 ether);
    }

    function testClaimCannotExceedPreRoundBalance() public {
        // owner mints 1 token to alice
        vm.prank(owner);
        collection.batchTokenMint(alice, defaultIds, defaultAmounts);

        // create round
        vm.prank(owner);
        collection.addClaimRound(uint128(block.timestamp + 10), 1 ether);

        // fund and approve alice
        dai.mint(alice, 5 ether);
        vm.prank(alice);
        dai.approve(address(collection), 5 ether);

        // warp into round
        vm.warp(block.timestamp + 11);

        // alice tries to claim 2 but preRoundBalance is 1 -> should revert
        vm.prank(alice);
        vm.expectRevert("already claimed max for holder");
        collection.claimTokens(0, 2);
    }

    // ----------------------------
    // Owner claim validations
    // ----------------------------
    function testOwnerClaimRevertsBeforeDeadline() public {
        vm.prank(owner);
        collection.addClaimRound(uint128(block.timestamp + 100), 1 ether);

        vm.prank(owner);
        vm.expectRevert("invalid round id"); // 0 is invalid when calling with 0
        collection.claimByOwner(0, 0);

        // claimByOwner for round 1 before deadline should revert "Deadline not passed"
        vm.prank(owner);
        vm.expectRevert("Deadline not passed");
        collection.claimByOwner(1, 0);
    }

    function testOwnerClaimZeroRoundReverts() public {
        // Explicit check: calling with roundId that doesn't exist (0) should revert
        vm.prank(owner);
        vm.expectRevert("invalid round id");
        collection.claimByOwner(0, 0);
    }

    // ----------------------------
    // Transfer allowlist / restriction tests
    // ----------------------------
    function testTransferNotAllowedReverts() public {
        // owner mints to alice
        vm.prank(owner);
        collection.batchTokenMint(alice, defaultIds, defaultAmounts);

        // alice tries to transfer token to bob but neither side is on allowlist -> revert
        vm.prank(alice);
        vm.expectRevert("Not allowed to transfer");
        collection.safeTransferFrom(alice, bob, 0, 1, "");
    }

    function testAllowedTransferSucceedsWhenAllowed() public {
        // owner mints to alice
        vm.prank(owner);
        collection.batchTokenMint(alice, defaultIds, defaultAmounts);

        // owner adds alice to allowlist
        vm.prank(owner);
        collection.addTransferAllowedAddress(alice);

        // alice transfers to bob successfully
        vm.prank(alice);
        collection.safeTransferFrom(alice, bob, 0, 1, "");

        assertEq(collection.balanceOf(bob, 0), 1);
        assertEq(collection.balanceOf(alice, 0), 0);
    }

    // ----------------------------
    // Batch owner claim flow and edgecases
    // ----------------------------
    function testBatchOwnerClaimRevertsForInvalidRoundInLoop() public {
        // Setup: create round 1
        vm.prank(owner);
        collection.addClaimRound(uint128(block.timestamp + 10), 1 ether);

        // Warp past end time
        vm.warp(block.timestamp + 10 + 30 days + 1);

        // calling batchOwnerClaim with roundId 1 should work (no revert) even if tokenIds include unknowns;
        // But calling with roundId == 0 must revert prior to loop.
        vm.prank(owner);
        vm.expectRevert("invalid round id");
        collection.batchOwnerClaim(0, defaultIds);
    }

    // ----------------------------
    // Misc / sanity
    // ----------------------------
    function testUriAfterSet() public {
        vm.prank(owner);
        collection.setURIs(defaultIds, defaultUris);
        assertEq(collection.uri(0), "ipfs://uri0");
        assertEq(collection.uri(1), "ipfs://uri1");
    }

    function testCannotAddZeroAddressToAllowlist() public {
        vm.prank(owner);
        vm.expectRevert("Invalid address");
        collection.addTransferAllowedAddress(address(0));
    }
}
