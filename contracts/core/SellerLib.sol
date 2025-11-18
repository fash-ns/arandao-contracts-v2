// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

library SellerLib {
    /// @notice Seller data structure for tracking sales and commissions
    struct Seller {
        uint256 bv; // Total business volume generated
        uint256 lastDnmWithdrawWeekNumber; // Seller's last week number of DNM withdraw
        uint256 createdAt; // Block timestamp of registration
        bool active; // Whether seller is active
    }

    /// @notice Emitted when a new seller is registered
    /// @param sellerId The assigned seller ID
    /// @param sellerAddr The seller's EOA address
    event SellerRegistered(
        uint256 indexed sellerId,
        address indexed sellerAddr
    );

    error SellerNotRegistered();
}
