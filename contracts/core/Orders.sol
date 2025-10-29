// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {OrderLib} from "./OrderLib.sol";

contract Orders {
  /// @notice Maps order IDs to Order structs
  mapping(uint256 => OrderLib.Order) orders;

  /// @notice Current highest order ID
  uint256 lastOrderId = 1;

  modifier onlyExistedOrder(uint256 orderId) {
    if (!orders[orderId].existed) {
      revert OrderLib.OrderNotExisted(orderId);
    }
    _;
  }

  function _createOrder(
    uint256 buyerId,
    uint256 sellerId,
    uint256 bv,
    uint256 sv
  ) internal {
    uint256 newOrderId = lastOrderId++;

    orders[newOrderId] = OrderLib.Order({
      buyerId: buyerId,
      sellerId: sellerId,
      sv: sv,
      bv: bv,
      existed: true,
      createdAt: block.timestamp
    });

    emit OrderLib.OrderCreated(newOrderId, buyerId, bv); //TODO: Change it and add sellerId, bv and sv
  }

  function _getOrderById(
    uint256 orderId
  ) internal view onlyExistedOrder(orderId) returns (OrderLib.Order storage) {
    return orders[orderId];
  }

  function getOrderById(
    uint256 orderId
  ) public view returns (OrderLib.Order memory) {
    return _getOrderById(orderId);
  }
}
