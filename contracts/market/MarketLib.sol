// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

library MarketLib {
  struct Product {
    address sellerAddress;
    uint256 bv;
    uint256 sv;
    bool active;
  }

  struct PurchaseProduct {
    uint256 productId;
    uint256 quantity;
  }

  event ProductCreated(
    address indexed sellerAddress,
    uint256 indexed tokenId,
    uint256 bv,
    uint256 sv,
    uint256 quantity
  );

  event SellerLockedArc(
    address indexed sellerAddress,
    uint256 amount,
    uint256 lockedAt
  );

  event SellerWithdrawnArc(address indexed sellerAddress, uint256 amount);

  event ProductPurchased(
    address indexed buyer,
    uint256 indexed productId,
    uint256 quantity
  );

  event ProductStatusChanged(uint256 indexed productId, bool isActive);
  
  event PurchaseCompleted(
    address indexed buyer,
    address indexed parentAddress,
    uint8 position,
    uint256 totalCoreTransferAmount,
    uint256 itemCount
  );

  error MarketBuyerInsufficientBalance(
    uint256 requiredBalance,
    uint256 availableBalance
  );
  error MarketSellerInsufficientBalance(
    uint256 requiredBalance,
    uint256 availableBalance
  );
  error MarketSellerArcNotLocked(address sellerAddress);
  error MarketProductInactive(uint256 productId);

  function calculatePayablePriceOfProduct(
    uint256 bv,
    uint256 sv
  ) internal pure returns (uint256) {
    return ((bv * 101) / 100) + sv;
  }

  function getSellerShare(
    uint256 bv,
    uint256 sv
  ) internal pure returns (uint256) {
    return sv - (bv / 100);
  }

  function getCommisionShare(uint256 bv) internal pure returns (uint256) {
    return (2 * bv) / 100;
  }
}
