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
        collection.batchOwnerClaim(0, new uint256[](0));

        vm.prank(owner);
        vm.expectRevert("Deadline not passed");
        collection.batchOwnerClaim(1, new uint256[](0));
    }

    function testOwnerClaimZeroRoundReverts() public {
        vm.prank(owner);
        vm.expectRevert("invalid round id");
        collection.batchOwnerClaim(0, new uint256[](0));
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

    // ════════════════════════════════════════════════════════════════════════
    // Coverage helpers
    // ════════════════════════════════════════════════════════════════════════

    function _mint1(address to, uint256 id, uint256 amount) internal {
        uint256[] memory ids = new uint256[](1);
        uint256[] memory amts = new uint256[](1);
        ids[0] = id;
        amts[0] = amount;
        vm.prank(owner);
        collection.batchTokenMint(to, ids, amts);
    }

    function _openRound(uint256 price) internal returns (uint128 start) {
        start = uint128(block.timestamp + 10);
        vm.prank(owner);
        collection.addClaimRound(start, price);
    }

    function _fundUsdt(address who, uint256 amount) internal {
        usdt.mint(who, amount);
        vm.prank(who);
        usdt.approve(address(collection), amount);
    }

    function _ids(uint256 a) internal pure returns (uint256[] memory ids) {
        ids = new uint256[](1);
        ids[0] = a;
    }

    // ════════════════════════════════════════════════════════════════════════
    // Constructor
    // ════════════════════════════════════════════════════════════════════════

    function testConstructorZeroUsdtReverts() public {
        vm.expectRevert("Invalid USDT address");
        new NftFundRaiseCollection(owner, address(0));
    }

    function testConstructorZeroOwnerReverts() public {
        // Ownable's constructor rejects the zero owner before the body runs.
        vm.expectRevert();
        new NftFundRaiseCollection(address(0), address(usdt));
    }

    // ════════════════════════════════════════════════════════════════════════
    // addClaimRound validation
    // ════════════════════════════════════════════════════════════════════════

    function testAddClaimRoundPastStartReverts() public {
        vm.warp(100);
        vm.prank(owner);
        vm.expectRevert("start must be future");
        collection.addClaimRound(uint128(50), 1 ether);
    }

    function testAddClaimRoundZeroUsdtReverts() public {
        vm.prank(owner);
        vm.expectRevert("invalid USDT amount");
        collection.addClaimRound(uint128(block.timestamp + 10), 0);
    }

    function testSecondRoundDisablesPreviousAndDoublesLimit() public {
        _openRound(1 ether); // round 1: maxMints = 1
        _openRound(2 ether); // round 2: maxMints = 2, round 1 disabled

        (,,, uint16 max1, bool enabled1) = collection.claimRounds(1);
        (,, uint256 price2, uint16 max2, bool enabled2) = collection.claimRounds(2);

        assertEq(max1, 1, "round 1 max wrong");
        assertFalse(enabled1, "round 1 should be disabled after round 2 opens");
        assertEq(max2, 2, "round 2 max should double");
        assertTrue(enabled2, "round 2 should be enabled");
        assertEq(price2, 2 ether, "round 2 price wrong");
        assertEq(collection.claimRound(), 2, "claimRound should be 2");
    }

    // ════════════════════════════════════════════════════════════════════════
    // claimTokens validation branches
    // ════════════════════════════════════════════════════════════════════════

    function testClaimBeforeStartTimeReverts() public {
        _mint1(alice, 0, 1);
        _openRound(1 ether); // starts at now + 10
        // Do not warp: currentTime < startTime.
        vm.prank(alice);
        vm.expectRevert("not in claim period");
        collection.claimTokens(0, 1);
    }

    function testClaimWithoutOwningTokenReverts() public {
        _mint1(alice, 0, 1); // alice owns; bob does not
        _openRound(1 ether);
        vm.warp(block.timestamp + 11);

        vm.prank(bob);
        vm.expectRevert("must own token to claim");
        collection.claimTokens(0, 1);
    }

    function testClaimExceedsRoundLimitReverts() public {
        _mint1(alice, 0, 5); // plenty of pre-round balance
        _openRound(1 ether); // round 1 max = 1
        _fundUsdt(alice, 10 ether);
        vm.warp(block.timestamp + 11);

        vm.prank(alice);
        collection.claimTokens(0, 1); // mints 1, round limit now reached

        vm.prank(alice);
        vm.expectRevert("exceeds claim limit");
        collection.claimTokens(0, 1);
    }

    function testClaimInconsistentClaimedStateReverts() public {
        _mint1(alice, 0, 2);
        _openRound(1 ether);
        _fundUsdt(alice, 10 ether);
        vm.warp(block.timestamp + 11);

        // Claim once: alreadyClaimed[0] = 1, balance = 3.
        vm.prank(alice);
        collection.claimTokens(0, 1);

        // Move all tokens to the owner (allowed because `to` is the owner), dropping
        // alice's balance below her recorded claimed amount.
        uint256 bal = collection.balanceOf(alice, 0);
        vm.prank(alice);
        collection.safeTransferFrom(alice, owner, 0, bal, "");
        assertEq(collection.balanceOf(alice, 0), 0);

        vm.prank(alice);
        vm.expectRevert("inconsistent claimed state");
        collection.claimTokens(0, 1);
    }

    // ════════════════════════════════════════════════════════════════════════
    // View accessors + claim accounting
    // ════════════════════════════════════════════════════════════════════════

    function testClaimUpdatesRoundAccounting() public {
        _mint1(alice, 0, 3);
        _openRound(1 ether); // round 1 max = 1
        _fundUsdt(alice, 10 ether);
        vm.warp(block.timestamp + 11);

        vm.prank(alice);
        collection.claimTokens(0, 1);

        assertEq(collection.mintedInRoundFor(1, 0), 1, "mintedInRoundFor wrong");
        assertEq(collection.alreadyClaimedInRound(1, 0, alice), 1, "alreadyClaimedInRound wrong");
    }

    // ════════════════════════════════════════════════════════════════════════
    // batchOwnerClaim
    // ════════════════════════════════════════════════════════════════════════

    function testOwnerClaimMintsUnclaimedToOwner() public {
        _mint1(alice, 0, 1);
        _openRound(1 ether); // round 1 max = 1, nobody claims
        vm.warp(block.timestamp + 11 + 30 days);

        uint256 before = collection.balanceOf(owner, 0);
        vm.prank(owner);
        collection.batchOwnerClaim(1, _ids(0));

        assertEq(collection.balanceOf(owner, 0) - before, 1, "owner should sweep the 1 unclaimed token");
        assertEq(collection.mintedInRoundFor(1, 0), 1, "round should be fully minted");
    }

    function testOwnerClaimRevertsWhenNothingUnclaimed() public {
        _mint1(alice, 0, 1);
        _openRound(1 ether); // round 1 max = 1
        _fundUsdt(alice, 10 ether);
        vm.warp(block.timestamp + 11);

        // Alice claims the only mintable token, exhausting the round.
        vm.prank(alice);
        collection.claimTokens(0, 1);

        vm.warp(block.timestamp + 30 days);
        vm.prank(owner);
        vm.expectRevert("No unclaimed tokens");
        collection.batchOwnerClaim(1, _ids(0));
    }

    // ════════════════════════════════════════════════════════════════════════
    // setURIs / disableSetUri
    // ════════════════════════════════════════════════════════════════════════

    function testSetURIsLengthMismatchReverts() public {
        string[] memory uris = new string[](1);
        uris[0] = "ipfs://x";
        vm.prank(owner);
        vm.expectRevert("Length mismatch");
        collection.setURIs(defaultIds, uris); // defaultIds has length 2
    }

    function testSetURIsAfterDisableReverts() public {
        vm.prank(owner);
        collection.disableSetUri();

        vm.prank(owner);
        vm.expectRevert("Set URI is already disabled.");
        collection.setURIs(defaultIds, defaultUris);
    }

    // ════════════════════════════════════════════════════════════════════════
    // Transfer allowlist management
    // ════════════════════════════════════════════════════════════════════════

    function testAddTransferAllowedTwiceReverts() public {
        vm.prank(owner);
        collection.addTransferAllowedAddress(alice);

        vm.prank(owner);
        vm.expectRevert("Already authorized");
        collection.addTransferAllowedAddress(bob);
    }

    function testAddTransferAllowedAfterDisableReverts() public {
        vm.prank(owner);
        collection.disableUpdateAllowedAddress();

        vm.prank(owner);
        vm.expectRevert("Transfer list updates disabled");
        collection.addTransferAllowedAddress(alice);
    }

    // ════════════════════════════════════════════════════════════════════════
    // MintHelper
    // ════════════════════════════════════════════════════════════════════════

    function testBatchMintArrayLengthMismatchReverts() public {
        uint256[] memory amts = new uint256[](1);
        amts[0] = 1;
        vm.prank(owner);
        vm.expectRevert("Array lengths must match");
        collection.batchTokenMint(alice, defaultIds, amts); // defaultIds length 2
    }
}
