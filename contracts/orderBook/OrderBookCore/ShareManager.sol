// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {OrderBookStorage} from "./BookStorage.sol";

/// @title ShareManager
/// @notice Handles the computation of revenue shares for sellers, platform (bv), and creators.
/// @dev Uses fixed ratios and integer arithmetic to ensure the sum of shares equals the total amount
abstract contract ShareManager is OrderBookStorage {
  /**
   * @dev Payment split logic (from total `total`):
   *
   * Current rules:
   *  • bv = 2 × seller
   *  • creator = 17% of bv
   *
   * Derivation:
   *  T = seller + bv + creator = S + 2S + 0.34S = 3.34S
   *  → seller = 50/167 × T
   *  → bv     = 100/167 × T
   *  → creator = 17/167 × T
   *
   * Solidity constants:
   *  DENOM = 167, SELLER_NUM = 50, BV_NUM = 100
   *  Creator share = DENOM - SELLER_NUM - BV_NUM = 17
   *
   * To update ratios:
   *  1. Set new bv_ratio (bv/seller) and creator_ratio (creator/bv)
   *  2. Compute seller = T / (1 + bv_ratio + bv_ratio * creator_ratio)
   *  3. Compute bv = seller × bv_ratio
   *  4. Compute creator = T - seller - bv
   *  5. Convert to integer numerators with a common denominator (DENOM)
   */

  /// @notice Computes individual shares (seller, bv, creator) from a total amount
  function _computeShares(
    uint256 total
  )
    internal
    view
    returns (uint256 sellerAmt, uint256 bvAmt, uint256 creatorAmt)
  {
    sellerAmt = (total * SELLER_NUM) / DENOM;
    bvAmt = (total * BV_NUM) / DENOM;
    creatorAmt = total - sellerAmt - bvAmt; // Remainder ensures exact total
  }

  /// @notice Computes the bv, creator, and total amounts given a seller amount
  function _computeFromSeller(
    uint256 seller
  ) internal view returns (uint256 bvAmt, uint256 creatorAmt, uint256 total) {
    bvAmt = (seller * BV_NUM) / SELLER_NUM; // bv = seller × BV_NUM / SELLER_NUM
    creatorAmt = (seller * (DENOM - SELLER_NUM - BV_NUM)) / SELLER_NUM; // creator = seller × 17 / 50
    total = seller + bvAmt + creatorAmt; // total = seller × DENOM / SELLER_NUM
  }
}
