// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

library SellerStruct {
  struct Seller {
    uint256 id;
    address sellerAddress;
    uint256 bv;
    bool exists;
  }

  error SellerNotFound(uint256 sellerId);

  event SellerCreated(uint256 indexed id, address indexed sellerAddress);
}
