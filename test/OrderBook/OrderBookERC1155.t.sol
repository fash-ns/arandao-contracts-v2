// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import {Test} from "forge-std/Test.sol";
import {MockERC1155} from "../mocks/MockERC1155.sol";
import {MockToken} from "../mocks/MockToken.sol";
import {NFTOrderBook} from "../../src/OrderBook/OrderBook.sol";

contract OrderBookERC1155Test is Test {
    MockERC1155 internal collection;
    MockToken internal usdt;
    NFTOrderBook internal orderBook;

    uint256 internal minPrice = 1e6;

    address internal owner = makeAddr("owner");
    address internal core = makeAddr("core");
    address internal bv = makeAddr("bv");
    address internal creator = makeAddr("creator");

    address internal user1 = makeAddr("user1");
    address internal user2 = makeAddr("user2");
    address internal parent = makeAddr("parent");

    function setUp() public {
        vm.startPrank(owner);

        collection = new MockERC1155("");
        usdt = new MockToken(user1, 1e25);

        // Deploy the new version: requires core contract + supported collection
        orderBook = new NFTOrderBook(owner, address(usdt), core, minPrice, address(collection));

        // Mint USDT to users
        usdt.mint(user1, 1e24);
        usdt.mint(user2, 1e24);

        // Mint NFTs to users
        collection.mint(user1, 1, 100, "");
        collection.mint(user1, 2, 100, "");
        collection.mint(user2, 3, 100, "");

        vm.stopPrank();
    }

    /*//////////////////////////////////////////////////////////////
                             Listing Tests
    //////////////////////////////////////////////////////////////*/
    function testListTokenForSale() public {
        vm.startPrank(user1);
        collection.setApprovalForAll(address(orderBook), true);

        // New signature: listTokenForSale(uint256 tokenId, uint256 sellerPrice, uint256 quantity)
        orderBook.listTokenForSale(1, minPrice * 2, 10);

        // Listing struct in storage: (seller, tokenId, quantity, sellerPrice, buyerPrice, active)
        (address seller, uint256 tokenId, uint256 quantity, uint256 sellerPrice, uint256 buyerPrice, bool active) =
            orderBook.listings(1);

        assertEq(seller, user1);
        assertEq(tokenId, 1);
        assertEq(quantity, 10);
        assertEq(sellerPrice, minPrice * 2);
        assertGt(buyerPrice, sellerPrice);
        assertTrue(active);

        // NFTs should be on the orderBook contract
        assertEq(collection.balanceOf(address(orderBook), 1), 10);

        vm.stopPrank();
    }

    function testListTokenForSaleFailsWithNoApproval() public {
        vm.startPrank(user1);
        vm.expectRevert(); // transfer will revert without approval
        orderBook.listTokenForSale(1, minPrice * 2, 5);
        vm.stopPrank();
    }

    function testListTokenForSaleFailsIfPriceTooLow() public {
        vm.startPrank(user1);
        collection.setApprovalForAll(address(orderBook), true);
        vm.expectRevert(bytes("Price below minimum"));
        orderBook.listTokenForSale(1, minPrice - 1, 5);
        vm.stopPrank();
    }

    function testCancelListing() public {
        vm.startPrank(user1);
        collection.setApprovalForAll(address(orderBook), true);
        orderBook.listTokenForSale(1, minPrice * 2, 5);

        // Cancel listing (seller is msg.sender)
        orderBook.cancelListForSale(1);

        (,,,,, bool active) = orderBook.listings(1);
        assertFalse(active, "Listing should be inactive after cancel");

        // NFTs returned to seller
        assertEq(collection.balanceOf(user1, 1), 100, "NFTs returned to seller");
        vm.stopPrank();
    }

    function testCancelListingFailsForNonOwner() public {
        vm.startPrank(user1);
        collection.setApprovalForAll(address(orderBook), true);
        orderBook.listTokenForSale(1, minPrice * 2, 5);
        vm.stopPrank();

        vm.prank(user2);
        vm.expectRevert(); // not listing owner
        orderBook.cancelListForSale(1);
    }

    // function testBuyListingPartial() public {
    //     // user1 lists 10 NFTs
    //     vm.startPrank(user1);
    //     collection.setApprovalForAll(address(orderBook), true);
    //     orderBook.listTokenForSale(1, minPrice * 2, 10);
    //     vm.stopPrank();

    //     // Get the buyerPrice from listing
    //     (, , , , uint256 buyerPrice, ) = orderBook.listings(1);

    //     uint256 usdtBeforeSeller = usdt.balanceOf(user1);
    //     uint256 usdtBeforeBuyer = usdt.balanceOf(user2);
    //     uint256 nftsBeforeOrderBook = collection.balanceOf(address(orderBook), 1);

    //     // user2 buys 5 NFTs
    //     vm.startPrank(user2);
    //     // buyListing(listingId, quantity, parent, position)
    //     usdt.approve(address(orderBook), buyerPrice * 5);
    //     orderBook.buyListing(1, 5, parent, 1);
    //     vm.stopPrank();

    //     // Check listing updated (should have 5 left)
    //     (, , uint256 remainingQty, , , bool active) = orderBook.listings(1);
    //     assertEq(remainingQty, 5, "Quantity should reduce after partial buy");
    //     assertTrue(active, "Listing still active after partial buy");

    //     // Check USDT balances moved (basic sanity checks)
    //     assertLt(usdt.balanceOf(user2), usdtBeforeBuyer, "Buyer spent USDT");
    //     assertGt(usdt.balanceOf(user1), usdtBeforeSeller, "Seller received USDT");

    //     // Check NFT balances
    //     assertEq(collection.balanceOf(user2, 1), 5, "User2 received 5 NFTs");
    //     assertEq(collection.balanceOf(address(orderBook), 1), nftsBeforeOrderBook - 5, "OrderBook NFT balance decreased");
    // }

    function testBuyListingFailsAfterCancel() public {
        // user1 lists 10 NFTs
        vm.startPrank(user1);
        collection.setApprovalForAll(address(orderBook), true);
        orderBook.listTokenForSale(1, minPrice * 2, 10);
        vm.stopPrank();

        // user1 cancels the listing
        vm.startPrank(user1);
        orderBook.cancelListForSale(1);
        vm.stopPrank();

        // user2 tries to buy after cancel -> should revert
        (,,,, uint256 buyerPrice,) = orderBook.listings(1);

        vm.startPrank(user2);
        usdt.approve(address(orderBook), buyerPrice * 5);
        vm.expectRevert(); // listing not active
        orderBook.buyListing(1, 5, parent, 1);
        vm.stopPrank();
    }

    /*//////////////////////////////////////////////////////////////
                         Offer Tests
    //////////////////////////////////////////////////////////////*/
    function testPlaceAndCancelOffer() public {
        uint256 price = minPrice * 2;
        uint256 qty = 5;

        vm.startPrank(user2);
        // placeOffer(tokenId, quantity, buyerPrice, parent, position)
        usdt.approve(address(orderBook), price * qty);
        orderBook.placeOffer(1, qty, price, parent, 1);

        // Offer struct: (buyer, tokenId, quantity, sellerPrice, buyerPrice, parentAddress, position, active)
        (address buyer, uint256 tokenId, uint256 storedQty,,, address parentAddr, uint8 pos, bool active) =
            orderBook.offers(1);

        assertEq(buyer, user2);
        assertEq(tokenId, 1);
        assertEq(storedQty, qty);
        assertTrue(active);
        assertEq(parentAddr, parent);
        assertEq(pos, 1);

        // Cancel offer
        orderBook.cancelOffer(1);
        (,,,,,,, bool activeAfter) = orderBook.offers(1);
        assertFalse(activeAfter, "Offer should be inactive after cancel");

        vm.stopPrank();
    }

    // function testAcceptOfferPartial() public {
    //     uint256 price = minPrice * 2;
    //     uint256 qty = 5;
    //     uint256 acceptQty = 3;

    //     // Buyer places offer
    //     vm.startPrank(user2);
    //     usdt.approve(address(orderBook), price * qty);
    //     orderBook.placeOffer(1, qty, price, parent, 1);
    //     vm.stopPrank();

    //     uint256 sellerUsdtBefore = usdt.balanceOf(user1);
    //     uint256 buyerNftBefore = collection.balanceOf(user2, 1);
    //     uint256 sellerNftBefore = collection.balanceOf(user1, 1);

    //     // Seller accepts part of the offer
    //     vm.startPrank(user1);
    //     collection.setApprovalForAll(address(orderBook), true);
    //     orderBook.acceptOffer(1, acceptQty);
    //     vm.stopPrank();

    //     // Offer tuple: (buyer, tokenId, quantity, sellerPrice, buyerPrice, parentAddress, position, active)
    //     ( , , uint256 remainingQty, ,, , , bool active) = orderBook.offers(1);
    //     assertEq(remainingQty, qty - acceptQty, "Remaining offer quantity mismatch");
    //     assertTrue(active, "Offer should still be active after partial accept");

    //     // Seller received USDT
    //     assertGt(usdt.balanceOf(user1), sellerUsdtBefore, "Seller should receive USDT for accepted NFTs");

    //     // NFT balances
    //     assertEq(collection.balanceOf(user1, 1), sellerNftBefore - acceptQty, "Seller's NFT balance should decrease");
    //     assertEq(collection.balanceOf(user2, 1), buyerNftBefore + acceptQty, "Buyer's NFT balance should increase");
    // }
}
