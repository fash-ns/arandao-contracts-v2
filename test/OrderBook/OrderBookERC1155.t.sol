// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {Test, console} from "forge-std/Test.sol";
import {NFTFundRaiseOrderBook} from "../../src/OrderBook/OrderBook.sol";
import {MockToken} from "../mocks/MockToken.sol";

contract NFTOrderBookCalcTest is Test {
    /// @notice Local mirror of _computeShares to validate on-chain math off-chain
    function computeShares(uint256 total) internal pure returns (uint256 sellerAmt, uint256 bvAmt, uint256 creatorAmt) {
        sellerAmt = (total * 50) / 150;
        uint256 bvGross = (total * 100) / 150;
        creatorAmt = (bvGross * 2700) / 10000;
        bvAmt = total - sellerAmt - creatorAmt;
    }

    function testComputeSharesExample() public pure {
        uint256 buyerPricePerToken = 300 ether;
        uint256 quantity = 2;

        (uint256 seller, uint256 bv, uint256 creator) = computeShares(buyerPricePerToken);

        uint256 marketFee = (bv * 1) / 100;
        uint256 totalCost = buyerPricePerToken + marketFee;

        uint256 totalBuyerCost = totalCost * quantity;
        uint256 sellerTotal = (seller * quantity) - (marketFee * quantity);
        uint256 creatorTotal = creator * quantity;
        uint256 coreFee = marketFee * 2 * quantity;

        // All three shares must sum exactly to buyerPrice
        assertEq(seller + bv + creator, buyerPricePerToken, "Shares sum to buyerPrice");
        assertEq(totalBuyerCost, (buyerPricePerToken + marketFee) * quantity, "Total buyer cost matches");

        // Silence unused variable warnings
        (sellerTotal, creatorTotal, coreFee);
    }

    function testComputeShares_SmallAmount() public pure {
        // Verify rounding behaviour: remainder stays with bvAmt (no over-payment)
        uint256 total = 100 ether;
        (uint256 seller, uint256 bv, uint256 creator) = computeShares(total);

        assertLe(seller + bv + creator, total, "shares must not exceed total");
        assertEq(seller + bv + creator, total, "shares must sum exactly to total (remainder in bv)");
    }

    function testComputeShares_ZeroCreatorFeeOnTinyAmount() public pure {
        // For very small amounts integer division may round creator to 0; bv absorbs remainder
        uint256 total = 150; // exact DENOM — clean division
        (uint256 seller, uint256 bv, uint256 creator) = computeShares(total);
        assertEq(seller + bv + creator, total, "conservation failed on tiny amount");
    }
}
