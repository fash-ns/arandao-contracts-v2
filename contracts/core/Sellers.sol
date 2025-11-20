// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {SellerLib} from "./SellerLib.sol";

contract Sellers {
  /// @notice Current highest seller ID for incremental assignment
  uint256 nextSellerId;

  /// @notice Maps seller addresses to compact numeric seller IDs
  mapping(address => uint256) addressToSellerId;

  /// @notice Maps seller ID to week to total BV for that week
  mapping(uint256 => mapping(uint256 => uint256)) public sellerWeeklyBv;

  /// @notice Maps seller IDs to Seller structs
  mapping(uint256 => SellerLib.Seller) sellers;

  modifier onlyRegisteredSeller(uint256 sellerId) {
    if (!sellers[sellerId].active) {
      revert SellerLib.SellerNotRegistered();
    }
    _;
  }

  function __Sellers_init() internal {
    nextSellerId = 1;
  }

  /**
   * @notice Internal method to get existing seller ID or create new seller
   * @param sellerAddr The seller's EOA address
   * @return sellerId The seller ID (existing or newly created)
   */
  function _getOrCreateSeller(address sellerAddr) internal returns (uint256) {
    uint256 sellerId = addressToSellerId[sellerAddr];

    // If seller doesn't exist, create them
    if (sellerId == 0) {
      sellerId = nextSellerId++;
      addressToSellerId[sellerAddr] = sellerId;

      sellers[sellerId] = SellerLib.Seller({
        bv: 0,
        lastDnmWithdrawWeekNumber: 0,
        createdAt: block.timestamp,
        active: true
      });

      emit SellerLib.SellerRegistered(sellerId, sellerAddr);
    }

    return sellerId;
  }

  function _addSellerBv(
    uint256 sellerId,
    uint256 weekNumber,
    uint256 amount
  ) internal onlyRegisteredSeller(sellerId) {
    sellers[sellerId].bv += amount;
    sellerWeeklyBv[sellerId][weekNumber] += amount;
  }

  function _getSellerById(
    uint256 sellerId
  )
    internal
    view
    onlyRegisteredSeller(sellerId)
    returns (SellerLib.Seller storage)
  {
    SellerLib.Seller storage seller = sellers[sellerId];

    return seller;
  }

  function getSellerById(
    uint256 sellerId
  ) public view returns (SellerLib.Seller memory) {
    return _getSellerById(sellerId);
  }

  function getSellerIdByAddress(
    address sellerAddress
  ) public view returns (uint256) {
    return addressToSellerId[sellerAddress];
  }
}
