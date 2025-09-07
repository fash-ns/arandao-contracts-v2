// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import {Test} from "forge-std/Test.sol";
import {MockERC1155} from  "./mocks/MockERC1155.sol";
import {MockToken} from "./mocks/MockToken.sol";
import {NFTOrderBook} from "../src/OrderBook.sol";

contract OrderBookERC1155Test is Test {
    MockERC1155 internal collection;
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

    address internal parent = makeAddr("parent");
    
    function setUp() public {
        vm.startPrank(owner);
        collection = new MockERC1155("");
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

        // Mint USDT to users
        usdt.mint(user1, 1e24);
        usdt.mint(user2, 1e24);

        // Mint NFTs
        collection.mint(user1, 1, 100, "");
        collection.mint(user1, 2, 100, "");
        collection.mint(user2, 2, 100, "");

        orderBook.registerCollection(address(collection), 1);

        vm.stopPrank();
    }

    /*//////////////////////////////////////////////////////////////
                             Collection Tests
    //////////////////////////////////////////////////////////////*/
    function testRegisterAndRemoveCollection() public {
        vm.startPrank(owner);
        orderBook.registerCollection(address(collection), 1);
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
        orderBook.registerCollection(address(collection), 1);
    }

    /*//////////////////////////////////////////////////////////////
                         Listing Tests
    //////////////////////////////////////////////////////////////*/
    function testListTokenForSale() public {
        vm.startPrank(user1);
        collection.setApprovalForAll(address(orderBook), true);
        
        orderBook.listTokenForSale(address(collection), 1, minPrice * 2, 10);
        (address seller,,, uint256 quantity, uint256 sellerPrice, uint256 buyerPrice, bool active) = orderBook.listings(1);

        uint256 nftBalanceOrderBook = collection.balanceOf(address(orderBook), 1);
        assertEq(nftBalanceOrderBook, quantity);
        
        assertEq(seller, user1);
        assertEq(quantity, 10);
        assertEq(sellerPrice, minPrice * 2);
        assertGt(buyerPrice, sellerPrice);
        assertTrue(active);
        vm.stopPrank();
    }

    function testListTokenForSaleFailsWithNoApproval() public {
        vm.startPrank(user1);
        vm.expectRevert();
        orderBook.listTokenForSale(address(collection), 1, minPrice * 2, 5);
        vm.stopPrank();
    }

    function testListTokenForSaleFailsIfPriceTooLow() public {
        vm.startPrank(user1);
        collection.setApprovalForAll(address(orderBook), true);
        vm.expectRevert(bytes("price must be >= minimum amount"));
        orderBook.listTokenForSale(address(collection), 1, minPrice - 1, 5);
        vm.stopPrank();
    }

    function testCancelListing() public {
        vm.startPrank(user1);
        collection.setApprovalForAll(address(orderBook), true);
        orderBook.listTokenForSale(address(collection), 1, minPrice * 2, 5);
        orderBook.cancelListForSale(1);

        (, ,,, , , bool active) = orderBook.listings(1);
        assertFalse(active, "Listing should be inactive after cancel");
        vm.stopPrank();
    }

    function testCancelListingFailsForNonOwner() public {
        vm.startPrank(user1);
        collection.setApprovalForAll(address(orderBook), true);
        orderBook.listTokenForSale(address(collection), 1, minPrice * 2, 5);
        vm.stopPrank();

        vm.prank(user2);
        vm.expectRevert();
        orderBook.cancelListForSale(1);
    }

    function testBuyListing() public {
        // user1 lists 10 NFTs
        vm.startPrank(user1);
        collection.setApprovalForAll(address(orderBook), true);
        orderBook.listTokenForSale(address(collection), 1, minPrice * 2, 10);
        vm.stopPrank();

        (, , , uint256 b_quantity , , uint256 buyerPrice, ) = orderBook.listings(1);
        assertEq(b_quantity, 10);

        // Record balances before purchase
        uint256 usdtBalanceUser2Before = usdt.balanceOf(user2);
        uint256 usdtBalanceUser1Before = usdt.balanceOf(user1);
        uint256 usdtBalanceBVBefore = usdt.balanceOf(bv);
        uint256 usdtBalanceCreatorBefore = usdt.balanceOf(creator);

        uint256 nftBalanceUser2Before = collection.balanceOf(user2, 1);
        uint256 nftBalanceOrderBookBefore = collection.balanceOf(address(orderBook), 1);

        // user2 buys 5 NFTs
        vm.startPrank(user2);
        usdt.approve(address(orderBook), buyerPrice * 5);
        orderBook.buyListing(1, 5, parent); // Partial purchase
        vm.stopPrank();

        // Check listing updated
        (, , , uint256 quantity, , , bool active) = orderBook.listings(1);
        assertEq(quantity, 5, "Quantity should reduce after partial buy");
        assertTrue(active, "Listing still active after partial buy");

        // Check USDT balances
        uint256 totalPaid = buyerPrice * 5;
        uint256 bvAmount = (totalPaid * bvNum) / denom;
        uint256 creatorAmount = totalPaid - ((totalPaid * sellerNum) / denom) - bvAmount;
        uint256 sellerAmount = totalPaid - bvAmount - creatorAmount;

        assertEq(usdt.balanceOf(user2), usdtBalanceUser2Before - totalPaid, "User2 USDT balance reduced correctly");
        assertEq(usdt.balanceOf(user1), usdtBalanceUser1Before + sellerAmount, "Seller received correct USDT");
        assertEq(usdt.balanceOf(bv), usdtBalanceBVBefore + bvAmount, "BV received correct USDT");
        assertEq(usdt.balanceOf(creator), usdtBalanceCreatorBefore + creatorAmount, "Creator received correct USDT");

        // Check NFT balances
        uint256 nftBalanceUser2After = collection.balanceOf(user2, 1);
        uint256 nftBalanceOrderBookAfter = collection.balanceOf(address(orderBook), 1);

        assertEq(nftBalanceUser2After, nftBalanceUser2Before + 5, "User2 received 5 NFTs");
        assertEq(nftBalanceOrderBookAfter, nftBalanceOrderBookBefore - 5, "OrderBook NFT balance reduced correctly");
    }

    function testBuyListingFailsAfterCancel() public {
        // user1 lists 10 NFTs
        vm.startPrank(user1);
        collection.setApprovalForAll(address(orderBook), true);
        orderBook.listTokenForSale(address(collection), 1, minPrice * 2, 10);
        vm.stopPrank();

        (, , , uint256 b_quantity , , uint256 buyerPrice, ) = orderBook.listings(1);
        assertEq(b_quantity, 10);

        // user1 cancels the listing
        vm.startPrank(user1);
        orderBook.cancelListForSale(1);
        vm.stopPrank();

        // user2 tries to buy after cancel -> should revert
        vm.startPrank(user2);
        usdt.approve(address(orderBook), buyerPrice * 5);
        vm.expectRevert(); // Listing not active
        orderBook.buyListing(1, 5, parent);
        vm.stopPrank();
    }

    function testPlaceOffer() public {
        uint256 pricePerNFT = minPrice * 2;
        uint256 quantity = 5;
        uint256 totalOffer = pricePerNFT * quantity;

        // Record balances before placing offer
        uint256 usdtBalanceUser2Before = usdt.balanceOf(user2);
        uint256 usdtBalanceOrderBookBefore = usdt.balanceOf(address(orderBook));

        // user2 places offer
        vm.startPrank(user2);
        usdt.approve(address(orderBook), 1e20);
        orderBook.placeOffer(address(collection), 1, quantity, pricePerNFT, parent);
        vm.stopPrank();

        // Offer state check
        (address buyer,,, uint256 storedQuantity, , , bool active) = orderBook.offers(1);
        assertEq(buyer, user2);
        assertEq(storedQuantity, quantity);
        assertTrue(active);

        // Balance checks
        assertEq(
            usdt.balanceOf(user2),
            usdtBalanceUser2Before - totalOffer,
            "User2 should lose USDT equal to offer total"
        );
        assertEq(
            usdt.balanceOf(address(orderBook)),
            usdtBalanceOrderBookBefore + totalOffer,
            "OrderBook should hold locked USDT"
        );
    }

    function testCancelOffer() public {
        vm.startPrank(user2);
        usdt.approve(address(orderBook), 1e20);
        orderBook.placeOffer(address(collection), 1, 5, minPrice * 2, parent);
        orderBook.cancelOffer(1);

        (, , , , , , bool active) = orderBook.offers(1);
        assertFalse(active, "Offer should be inactive after cancel");
        vm.stopPrank();
    }

    function testAcceptOffer() public {
        uint256 pricePerNFT = minPrice * 2;
        uint256 offerQuantity = 5;
        uint256 acceptQuantity = 3;

        // user2 places offer
        vm.startPrank(user2);
        usdt.approve(address(orderBook), 1e20);
        orderBook.placeOffer(address(collection), 1, offerQuantity, pricePerNFT, parent);
        vm.stopPrank();

        // Record balances before acceptance
        uint256 user1UsdtBefore = usdt.balanceOf(user1);
        // uint256 user2UsdtBefore = usdt.balanceOf(user2);
        // uint256 orderBookUsdtBefore = usdt.balanceOf(address(orderBook));

        uint256 user1NftBefore = collection.balanceOf(user1, 1);
        uint256 user2NftBefore = collection.balanceOf(user2, 1);

        // user1 accepts part of the offer
        vm.startPrank(user1);
        collection.setApprovalForAll(address(orderBook), true);
        orderBook.acceptOffer(1, acceptQuantity); // Partial acceptance
        vm.stopPrank();

        // Offer state check
        (, , , uint256 remainingQuantity, uint256 sellerAmount, , bool active) = orderBook.offers(1);
        assertEq(remainingQuantity, offerQuantity - acceptQuantity, "Remaining offer quantity mismatch");
        assertTrue(active, "Offer should still be active after partial accept");

        assertEq(
            usdt.balanceOf(user1),
            user1UsdtBefore + (sellerAmount * acceptQuantity),
            "Seller should receive USDT for accepted NFTs"
        );

        // NFT balance checks
        assertEq(
            collection.balanceOf(user1, 1),
            user1NftBefore - acceptQuantity,
            "Seller's NFT balance should decrease"
        );
        assertEq(
            collection.balanceOf(user2, 1),
            user2NftBefore + acceptQuantity,
            "Buyer's NFT balance should increase"
        );
    }
   
}