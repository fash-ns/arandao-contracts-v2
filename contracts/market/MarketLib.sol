// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

library MarketLib {
  struct Product {
    address sellerAddress;
    uint256 bv;
    uint256 uv;
  }

  struct PurchaseProduct {
    uint256 productId;
    uint256 quantity;
  }

  event ProductCreated(
    address indexed sellerAddress,
    uint256 indexed tokenId,
    uint256 bv,
    uint256 uv
  );
  event SellerLockedDnm(address indexed sellerAddress);
  event SellerWithdrawnDnm(address sellerAddress);

  error MarketBuyerInsufficientBalance(
    uint256 requiredBalance,
    uint256 availableBalance
  );
  error MarketSellerInsufficientBalance(
    uint256 requiredBalance,
    uint256 availableBalance
  );
  error MarketSellerDnmNotLocked(address sellerAddress);

  function calculatePayablePriceOfProduct(
    uint256 bv,
    uint256 uv
  ) internal pure returns (uint256) {
    return ((bv * 101) / 100) + uv;
  }

  function getSellerShare(
    uint256 bv,
    uint256 uv
  ) internal pure returns (uint256) {
    return uv - (bv / 100);
  }

  function getCommisionShare(uint256 bv) internal pure returns (uint256) {
    return (2 * bv) / 100;
  }
}
