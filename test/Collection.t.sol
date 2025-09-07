// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import "forge-std/Test.sol";
import "../src/Collection.sol";

contract MyTokenTest is Test {
    MyToken internal token;

    address[] recipients;
    string[] uris;

    address internal owner = makeAddr("owner");
    address internal alice = makeAddr("alice");
    address internal bob = makeAddr("bob");
    address internal charlie = makeAddr("charlie");

    function setUp() public {
        token = new MyToken(owner);
    }

    // ----------------------------
    // Deployment
    // ----------------------------
    function testDeployment() public view {
        assertEq(token.name(), "MyToken");
        assertEq(token.symbol(), "MTK");
        assertEq(token.nextTokenId(), 1);
        assertEq(token.MAX_SUPPLY(), 1000);
        assertEq(token.owner(), owner);
    }

    // ----------------------------
    // Ownership
    // ----------------------------
    function testTransferOwnerShip() public {
        address newOwner = makeAddr("newOwner");
        vm.startPrank(owner);
        token.transferOwnership(newOwner);

        assertTrue(token.ownershipFlag());

        address currentOwner = token.owner();
        assertEq(currentOwner, newOwner);
    }

    function test_RevertTransferOwnerShipWithZeroAddress() public {
        address newOwner = address(0);
        vm.startPrank(owner);
        vm.expectRevert();
        token.transferOwnership(newOwner);

        assertFalse(token.ownershipFlag());
        address currentOwner = token.owner();
        assertEq(currentOwner, owner);
    }

    function test_RevertSecoendTransferOwnerShip() public {
        address newOwner = makeAddr("newOwner");
        vm.startPrank(owner);
        token.transferOwnership(newOwner);
        vm.stopPrank();

        vm.startPrank(newOwner);
        vm.expectRevert("Ownership has already been transferred");
        token.transferOwnership(owner);

    }

    // ----------------------------
    // Minting
    // ----------------------------
    function testSafeMintIncrementsIdAndSetsURI() public {
        vm.prank(owner);
        token.safeMint(alice, "ipfs://token1");

        assertEq(token.nextTokenId(), 2);
        assertEq(token.ownerOf(1), alice);
        assertEq(token.tokenURI(1), "ipfs://token1");
    }

    function testNonOwnerCannotMint() public {
        vm.prank(alice);
        vm.expectRevert();
        token.safeMint(alice, "ipfs://fail");
    }

    function testBatchMintWorks() public {
        recipients.push(alice);
        recipients.push(bob);

        uris.push("ipfs://a");
        uris.push("ipfs://b");

        vm.prank(owner);
        token.safeBatchMint(recipients, uris);

        assertEq(token.ownerOf(1), alice);
        assertEq(token.ownerOf(2), bob);
        assertEq(token.tokenURI(1), "ipfs://a");
        assertEq(token.tokenURI(2), "ipfs://b");
    }

    function testBatchMintRevertsOnMismatchedArrays() public {
        recipients.push(alice);

        uris.push("ipfs://a");
        uris.push("ipfs://extra");

        vm.prank(owner);
        vm.expectRevert("Mismatched arrays");
        token.safeBatchMint(recipients, uris);
    }

    function testMaxSupplyReached() public {
        vm.startPrank(owner);
        for (uint256 i = 0; i < token.MAX_SUPPLY(); i++) {
            token.safeMint(alice, "ipfs://x");
        }
        vm.expectRevert("Max supply reached");
        token.safeMint(alice, "ipfs://overflow");
        vm.stopPrank();
    }

    // ----------------------------
    // Transfer Restrictions
    // ----------------------------
    function testTransferNotAllowedByDefault() public {
        vm.startPrank(owner);
        token.safeMint(alice, "ipfs://x");
        vm.stopPrank();

        vm.prank(alice);
        vm.expectRevert("Not allowed to transfer");
        token.transferFrom(alice, bob, 1);
    }

    function testOwnerCanAuthorizeTransfer() public {
        vm.startPrank(owner);
        token.safeMint(alice, "ipfs://x");
        token.addTransferAllowedAddress(alice);
        vm.stopPrank();

        vm.prank(alice);
        token.transferFrom(alice, bob, 1);

        assertEq(token.ownerOf(1), bob);
    }

    function testReceiverAuthorizationWorks() public {
        vm.startPrank(owner);
        token.safeMint(alice, "ipfs://x");
        token.addTransferAllowedAddress(bob);
        vm.stopPrank();

        vm.prank(alice);
        token.transferFrom(alice, bob, 1);

        assertEq(token.ownerOf(1), bob);
    }

    function testRemoveTransferAllowedAddress() public {
        vm.startPrank(owner);
        token.safeMint(alice, "ipfs://x");
        token.addTransferAllowedAddress(alice);
        token.removeTransferAllowedAddress(alice);
        vm.stopPrank();

        vm.prank(alice);
        vm.expectRevert("Not allowed to transfer");
        token.transferFrom(alice, bob, 1);
    }

    function testAddTransferAllowedAddressValidations() public {
        vm.startPrank(owner);

        vm.expectRevert("Invalid address");
        token.addTransferAllowedAddress(address(0));

        token.addTransferAllowedAddress(alice);
        vm.expectRevert("Already authorized");
        token.addTransferAllowedAddress(alice);

        vm.stopPrank();
    }

    function testRemoveTransferAllowedAddressValidations() public {
        vm.prank(owner);
        vm.expectRevert("Not authorized");
        token.removeTransferAllowedAddress(alice);
    }

    // ----------------------------
    // Interfaces
    // ----------------------------
    function testSupportsERC721Interface() public view {
        assertTrue(token.supportsInterface(0x80ac58cd)); // ERC721
    }

    function testSupportsERC721MetadataInterface() public view {
        assertTrue(token.supportsInterface(0x5b5e139f)); // ERC721Metadata
    }
}
