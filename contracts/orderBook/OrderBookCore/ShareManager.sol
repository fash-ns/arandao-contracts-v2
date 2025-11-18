// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {OrderBookStorage} from "./BookStorage.sol";

/// @title ShareManager
/// @notice Handles the computation of revenue shares for sellers, platform (bv), and creators.
/// @dev Uses fixed ratios and integer arithmetic to ensure the sum of shares equals the total amount
abstract contract ShareManager is OrderBookStorage {
    /**
     * @notice Computes the distribution from total amount.
     * @param total Total value to split.
     * @return sellerAmt Seller share
     * @return bvAmt BV share (after creator fee deducted)
     * @return creatorAmt Creator fee (27% of BV)
     */
    function _computeShares(
        uint256 total
    )
        internal
        pure
        returns (uint256 sellerAmt, uint256 bvAmt, uint256 creatorAmt)
    {
        sellerAmt = (total * SELLER_NUM) / DENOM;
        uint256 bvGross = (total * BV_NUM) / DENOM;
        creatorAmt = (bvGross * CREATOR_FEE_BPS) / 10000;
        bvAmt = total - sellerAmt - creatorAmt; // use remainder to ensure total consistency
    }

    /**
     * @notice Computes BV, creator, and total amounts given a seller amount.
     * @param seller Seller’s amount.
     * @return bvAmt BV net (after creator fee)
     * @return creatorAmt Creator’s fee
     * @return total Total combined
     */
    function _computeFromSeller(
        uint256 seller
    ) internal pure returns (uint256 bvAmt, uint256 creatorAmt, uint256 total) {
        // Compute gross BV
        uint256 bvGross = (seller * BV_NUM) / SELLER_NUM;

        // Creator fee from BV
        creatorAmt = (bvGross * CREATOR_FEE_BPS) / 10000;

        // BV after paying creator
        bvAmt = bvGross - creatorAmt;

        // Total recomputed
        total = seller + bvAmt + creatorAmt;
    }
}
