// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

library OrderLib {
    /// @notice Order data structure for tracking purchases
    struct Order {
        uint256 buyerId; // User ID who made the purchase
        uint256 sellerId; // Seller ID who made the sale
        uint256 sv; // Sales value
        uint256 bv; // Business value
        bool existed;
        uint256 createdAt; // Block timestamp of order
    }

    /// @notice Emitted when a new order is created
    /// @param orderId The assigned order ID
    /// @param buyerId The user ID who made the purchase
    /// @param sellerId The seller ID of the order
    /// @param bv The purchase business value
    /// @param sv The purchase seller value
    event OrderCreated(
        uint256 indexed orderId,
        uint256 indexed buyerId,
        uint256 indexed sellerId,
        uint256 bv,
        uint256 sv
    );

    error OrderNotExisted(uint256 orderId);
}
