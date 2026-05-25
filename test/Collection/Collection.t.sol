// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {Test} from "forge-std/Test.sol";
import {NftFundRaiseCollection} from "../../src/Collection/Collection.sol";
import {MockToken} from "../mocks/MockToken.sol";

contract NftFundRaiseCollectionExtraTest is Test {
    NftFundRaiseCollection internal collection;
    MockToken internal usdt;

    address internal owner = makeAddr("owner");
    address internal alice = makeAddr("alice");
    address internal bob = makeAddr("bob");
    address internal attacker = makeAddr("attacker");

    uint256[] internal defaultIds;
    uint256[] internal defaultAmounts;
    string[] internal defaultUris;

    function setUp() public {
        usdt = new MockToken(address(3), 1_000_000 ether);
        collection = new NftFundRaiseCollection(owner, address(usdt));

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

        vm.prank(newOwner);
        vm.expectRevert("Ownership has already been transferred");
        collection.transferOwnership(owner);
    }

    function testRenounceOwnershipIsDisabled() public {
        vm.prank(owner);
        vm.expectRevert("Renouncing ownership is disabled");
        collection.renounceOwnership();
    }

    // ----------------------------
    // Initial mint phase
    // ----------------------------
    function testMintBlockedAfterDisableInitialMint() public {
        vm.startPrank(owner);
        collection.batchTokenMint(alice, defaultIds, defaultAmounts);
        collection.disableInitialMint();

        vm.expectRevert("Mint is not enable");
        collection.batchTokenMint(bob, defaultIds, defaultAmounts);
        vm.stopPrank();
    }

    function testOwnerCanMintMultipleTimesBeforeDisable() public {
        vm.startPrank(owner);
        collection.batchTokenMint(alice, defaultIds, defaultAmounts);
        collection.batchTokenMint(bob, defaultIds, defaultAmounts);
        vm.stopPrank();

        assertEq(collection.balanceOf(alice, 0), 1);
        assertEq(collection.balanceOf(bob, 0), 1);
    }

    // ----------------------------
    // Claim round / validation edge cases
    // ----------------------------
    function testClaimBeforeAnyRoundReverts() public {
        vm.prank(alice);
        vm.expectRevert("no active round");
        collection.claimTokens(0, 1);
    }

    function testClaimWithZeroAmountReverts() public {
        vm.prank(owner);
        collection.batchTokenMint(alice, defaultIds, defaultAmounts);

        vm.prank(owner);
        collection.addClaimRound(uint128(block.timestamp + 10), 1 ether);

        vm.warp(block.timestamp + 11);

        vm.prank(alice);
        vm.expectRevert("invalid amount");
        collection.claimTokens(0, 0);
    }

    function testClaimRevertsIfNoUSDTApprovalOrInsufficient() public {
        vm.prank(owner);
        collection.batchTokenMint(alice, defaultIds, defaultAmounts);

        vm.prank(owner);
        collection.addClaimRound(uint128(block.timestamp + 10), 1 ether);

        vm.warp(block.timestamp + 11);

        vm.prank(alice);
        vm.expectRevert();
        collection.claimTokens(0, 1);
    }

    function testClaimTransfersUSDTToOwner() public {
        vm.startPrank(owner);
        collection.batchTokenMint(alice, defaultIds, defaultAmounts);
        collection.addClaimRound(uint128(block.timestamp + 10), 1 ether);
        vm.stopPrank();

        usdt.mint(alice, 5 ether);
        vm.prank(alice);
        usdt.approve(address(collection), 5 ether);

        vm.warp(block.timestamp + 11);

        uint256 before = usdt.balanceOf(owner);
        vm.prank(alice);
        collection.claimTokens(0, 1);

        assertEq(usdt.balanceOf(owner), before + 1 ether);
    }

    function testClaimCannotExceedPreRoundBalance() public {
        vm.prank(owner);
        collection.batchTokenMint(alice, defaultIds, defaultAmounts);

        vm.prank(owner);
        collection.addClaimRound(uint128(block.timestamp + 10), 1 ether);

        usdt.mint(alice, 5 ether);
        vm.prank(alice);
        usdt.approve(address(collection), 5 ether);

        vm.warp(block.timestamp + 11);

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
        vm.expectRevert("invalid round id");
        collection.claimByOwner(0, 0);

        vm.prank(owner);
        vm.expectRevert("Deadline not passed");
        collection.claimByOwner(1, 0);
    }

    function testOwnerClaimZeroRoundReverts() public {
        vm.prank(owner);
        vm.expectRevert("invalid round id");
        collection.claimByOwner(0, 0);
    }

    // ----------------------------
    // Transfer allowlist / restriction tests
    // ----------------------------
    function testTransferNotAllowedReverts() public {
        vm.prank(owner);
        collection.batchTokenMint(alice, defaultIds, defaultAmounts);

        vm.prank(alice);
        vm.expectRevert("Not allowed to transfer");
        collection.safeTransferFrom(alice, bob, 0, 1, "");
    }

    function testAllowedTransferSucceedsWhenAllowed() public {
        vm.prank(owner);
        collection.batchTokenMint(alice, defaultIds, defaultAmounts);

        vm.prank(owner);
        collection.addTransferAllowedAddress(alice);

        vm.prank(alice);
        collection.safeTransferFrom(alice, bob, 0, 1, "");

        assertEq(collection.balanceOf(bob, 0), 1);
        assertEq(collection.balanceOf(alice, 0), 0);
    }

    // ----------------------------
    // Batch owner claim
    // ----------------------------
    function testBatchOwnerClaimRevertsForInvalidRoundInLoop() public {
        vm.prank(owner);
        collection.addClaimRound(uint128(block.timestamp + 10), 1 ether);

        vm.warp(block.timestamp + 10 + 30 days + 1);

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
