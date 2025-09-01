// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import {Test} from "forge-std/Test.sol";
import {MyToken} from  "../src/Collection.sol";
import {MockToken} from "./mocks/MockToken.sol";
import {NFTOrderBook} from "../src/OrderBook.sol";

contract OrderBookERC721Test is Test {
    MyToken internal collection;
    MockToken internal usdt;
    NFTOrderBook internal orderBook;

    uint256 denom = 167;
    uint256 sellerNum = 50;
    uint256 bvNum = 100;

    uint256 minPrice = 1e6;

    address internal owner = makeAddr("owner");
    address internal bv = makeAddr("bv");
    address internal creator = makeAddr("creator");

    address internal user1 = makeAddr("user1");
    address internal user2 = makeAddr("user2");
    
    function setUp() public {
        vm.startPrank(owner);
        collection = new MyToken(owner);
        usdt = new MockToken(user1, 1e25);

        orderBook = new NFTOrderBook(
            owner, 
            address(usdt),
            bv,
            creator,
            denom,
            sellerNum,
            bvNum,
            minPrice
        );

        orderBook.registerCollection(
            address(collection), 0
        );

        // Mint USDT to users
        usdt.mint(user1, 1e24);
        usdt.mint(user2, 1e24);

        // Mint NFTs
        collection.safeMint(user1, "");
        collection.safeMint(user1, "");
        collection.safeMint(user2, "");

        collection.addTransferAllowedAddress(address(orderBook));

        vm.stopPrank();
    }

    /*//////////////////////////////////////////////////////////////
                             Collection Tests
    //////////////////////////////////////////////////////////////*/
    function testRegisterAndRemoveCollection() public {
        vm.startPrank(owner);
        orderBook.registerCollection(address(collection), 0);
        (, bool exists) = orderBook.collections(address(collection));
        assertTrue(exists, "Collection should exist");

        orderBook.removeCollection(address(collection));
        (, exists) = orderBook.collections(address(collection));
        assertFalse(exists, "Collection should be removed");
        vm.stopPrank();
    }

    function testOnlyOwnerCanRegisterCollection() public {
        vm.prank(user1);
        vm.expectRevert();
        orderBook.registerCollection(address(collection), 0);
    }

    /*//////////////////////////////////////////////////////////////
                         Listing Tests
    //////////////////////////////////////////////////////////////*/
    function testListTokenForSale() public {
        vm.startPrank(user1);
        collection.setApprovalForAll(address(orderBook), true);
        uint256 tokenId = 1;

        orderBook.listTokenForSale(address(collection), tokenId, minPrice * 2, 1);
        (address seller,,,, uint256 sellerPrice, uint256 buyerPrice, bool active) = orderBook.listings(1);

        assertGt(buyerPrice, sellerPrice);

        assertEq(seller, user1);
        assertEq(sellerPrice, minPrice * 2);
        assertTrue(active);

        address newOwner = collection.ownerOf(tokenId);
        assertEq(newOwner, address(orderBook));

        vm.stopPrank();
    }

    function testListTokenForSaleFailsWithNoApproval() public {
        vm.startPrank(user1);
        // collection.setApprovalForAll(address(orderBook), true);
        uint256 tokenId = 1;

        vm.expectRevert();
        orderBook.listTokenForSale(address(collection), tokenId, minPrice * 2, 1);

        vm.stopPrank();
    }

    function testListTokenForSaleFailsIfPriceTooLow() public {
        vm.startPrank(user1);
        collection.setApprovalForAll(address(orderBook), true);
        vm.expectRevert(bytes("price must be >= minimum amount"));
        orderBook.listTokenForSale(address(collection), 1, minPrice - 1, 1);
        vm.stopPrank();
    }

    function testCancelListing() public {
        vm.startPrank(user1);

        collection.setApprovalForAll(address(orderBook), true);
        orderBook.listTokenForSale(address(collection), 1, minPrice * 2, 1);
        orderBook.cancelListForSale(1);

        (, ,uint256 tokenId , , , , bool active) = orderBook.listings(1);
        assertFalse(active, "Listing should be inactive after cancel");

        address newOwner = collection.ownerOf(tokenId);
        assertEq(newOwner, user1);

        vm.stopPrank();
    }

    function testCancelListingFailsForNonOwner() public {
        vm.startPrank(user1);
        collection.setApprovalForAll(address(orderBook), true);
        orderBook.listTokenForSale(address(collection), 1, minPrice * 2, 1);
        vm.stopPrank();

        vm.prank(user2);
        vm.expectRevert();
        orderBook.cancelListForSale(1);
    }

    function testBuyListing() public {
        vm.startPrank(user1);
        collection.setApprovalForAll(address(orderBook), true);

        uint256 sellerPrice = minPrice * 2;
        orderBook.listTokenForSale(address(collection), 1, sellerPrice, 1);

        vm.stopPrank();

        (,,,,, uint256 buyerPrice,) = orderBook.listings(1);

        // user2 approves USDT
        vm.startPrank(user2);
        usdt.approve(address(orderBook), buyerPrice);
        orderBook.buyListing(1, 1);
        vm.stopPrank();

        uint256 bvBalance = usdt.balanceOf(bv);
        uint256 creatorBalance = usdt.balanceOf(creator);
        assertEq(sellerPrice, buyerPrice - (bvBalance + creatorBalance));

        (,, , , , , bool active) = orderBook.listings(1);
        assertFalse(active, "Listing should be inactive after purchase");
    }

    function testBuyListingFailsWithSellerPrice() public {
        vm.startPrank(user1);
        collection.setApprovalForAll(address(orderBook), true);
        uint256 sellerPrice = minPrice * 2;
        orderBook.listTokenForSale(address(collection), 1, sellerPrice, 1);
        vm.stopPrank();

        // user2 approves USDT
        vm.startPrank(user2);
        usdt.approve(address(orderBook), sellerPrice);
        vm.expectRevert();
        orderBook.buyListing(1, 1);
        vm.stopPrank();
    }

    function testBuyOwnListingFails() public {
        vm.startPrank(user1);
        collection.setApprovalForAll(address(orderBook), true);
        orderBook.listTokenForSale(address(collection), 1, minPrice * 2, 1);
        usdt.approve(address(orderBook), 1e20);
        vm.expectRevert();
        orderBook.buyListing(1, 1);
        vm.stopPrank();
    }

    /*//////////////////////////////////////////////////////////////
                         Offer Tests
    //////////////////////////////////////////////////////////////*/
    function testPlaceOffer() public {
        vm.startPrank(user2);
        usdt.approve(address(orderBook), 1e20);
        orderBook.placeOffer(address(collection), 1, 1, minPrice * 2);
        vm.stopPrank();

        (address buyer,,, uint256 quantity,, , bool active) = orderBook.offers(1);
        assertEq(buyer, user2);
        assertEq(quantity, 1);
        assertTrue(active);
    }

    function testCancelOffer() public {
        vm.startPrank(user2);
        usdt.approve(address(orderBook), 1e20);
        orderBook.placeOffer(address(collection), 1, 1, minPrice * 2);
        orderBook.cancelOffer(1);
        (, , , , , , bool active) = orderBook.offers(1);
        assertFalse(active, "Offer should be inactive after cancel");
        vm.stopPrank();
    }

    function testAcceptOffer() public {
        // user2 places offer
        vm.startPrank(user2);
        uint256 buyAmount = minPrice * 2;
        usdt.approve(address(orderBook), buyAmount);
        orderBook.placeOffer(address(collection), 1, 1, buyAmount);
        vm.stopPrank();

        // user1 owns NFT and accepts
        vm.startPrank(user1);
        collection.setApprovalForAll(address(orderBook), true);
        orderBook.acceptOffer(1, 1);
        (, , , , uint256 sellerAmount, , bool active) = orderBook.offers(1);

        uint256 bvBalance = usdt.balanceOf(bv);
        uint256 creatorBalance = usdt.balanceOf(creator);
        assertEq(buyAmount, bvBalance + creatorBalance + sellerAmount);

        assertFalse(active, "Offer should be inactive after acceptance");
        vm.stopPrank();
    }

    function testERC721QuantityEnforced() public {
        vm.startPrank(user1);
        collection.setApprovalForAll(address(orderBook), true);
        vm.expectRevert(bytes("ERC721 quantity must be 1"));
        orderBook.listTokenForSale(address(collection), 1, minPrice * 2, 2);
        vm.stopPrank();
    }

}