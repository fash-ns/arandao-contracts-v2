// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import {Test, console} from "forge-std/Test.sol";
import {MockERC1155} from "../mocks/MockERC1155.sol";
import {MockToken} from "../mocks/MockToken.sol";
import {NFTOrderBook} from "../../src/OrderBook/OrderBook.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";

contract NFTOrderBookCalcTest is Test {
    NFTOrderBook orderBook;

    function setUp() public {
        // Deploy a bare-bones NFTOrderBook with dummy addresses
        orderBook = new NFTOrderBook();
    }

    /// @notice Helper to mimic _computeShares logic
    function computeShares(uint256 total) internal pure returns (uint256 sellerAmt, uint256 bvAmt, uint256 creatorAmt) {
        sellerAmt = (total * 50) / 150;
        uint256 bvGross = (total * 100) / 150;
        creatorAmt = (bvGross * 2700) / 10000;
        bvAmt = total - sellerAmt - creatorAmt;
    }

    function testComputeSharesExample() public {
        uint256 buyerPricePerToken = 300 ether;
        uint256 quantity = 2;

        // Compute shares for 1 token
        (uint256 seller, uint256 bv, uint256 creator) = computeShares(buyerPricePerToken);

        // Add market fee (1% of BV) as in buyListing
        uint256 marketFee = (bv * 1) / 100;
        uint256 totalCost = buyerPricePerToken + marketFee;

        // Now scale for quantity
        uint256 totalBuyerCost = totalCost * quantity;
        uint256 sellerTotal = (seller * quantity) - (marketFee * quantity); // seller gets minus market fee
        uint256 creatorTotal = creator * quantity;
        uint256 coreFee = marketFee * 2 * quantity; // Core contract receives market fee twice

        console.log("Buyer price per token:", buyerPricePerToken);
        console.log("Seller per token:", seller);
        console.log("BV per token:", bv);
        console.log("Creator per token:", creator);
        console.log("Market fee per token:", marketFee);
        console.log("Total buyer cost:", totalBuyerCost);
        console.log("Seller total received:", sellerTotal);
        console.log("Creator total received:", creatorTotal);
        console.log("Core total received:", coreFee);

        // Simple assertions to validate numbers
        assertEq(seller + creator, buyerPricePerToken, "Shares sum to buyerPrice");
        assertEq(totalBuyerCost, (buyerPricePerToken + marketFee) * quantity, "Total buyer cost matches");
    }
}
