// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

interface ICreateOrder {
  struct CreateOrderStruct {
    address sellerAddress;
    uint256 sv; // Seller value
    uint256 bv; // Business value
  }

  function createOrder(
    address buyerAddress,
    address parentAddress,
    uint8 position,
    CreateOrderStruct[] calldata orders
  ) external;
}
