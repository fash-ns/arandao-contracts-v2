// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {OrderBookStorage} from "./BookStorage.sol";

/// @title ListingManager
/// @notice Abstract contract responsible for managing listings in the order book, including creation, cancellation, and purchases.
/// @dev Inherits storage from OrderBookStorage
abstract contract ListingManager is OrderBookStorage {
  /// @notice Emitted when a new listing is created
  event ListingCreated(
    uint256 indexed listingId,
    address indexed seller,
    address collection,
    uint256 tokenId,
    uint256 sellerPrice,
    uint256 buyerPrice,
    uint256 quantity
  );

  /// @notice Emitted when a listing is cancelled
  event ListingCancelled(uint256 indexed listingId, address indexed seller);

  /// @notice Emitted when a listing is partially or fully purchased
  event ListingPurchased(
    uint256 indexed listingId,
    address indexed seller,
    address indexed buyer
  );

  /// @notice Emitted when a listing is fully executed (all quantity sold)
  event ListingExecuted(uint256 indexed listingId, address indexed buyer);

  /// @notice Internal function to create a new listing
  /// @dev Automatically assigns a unique listing ID and stores the listing
  /// @param seller Address of the seller
  /// @param collection Address of the NFT collection
  /// @param tokenId Token ID of the NFT
  /// @param sellerPrice Price the seller wants
  /// @param buyerPrice Price for instant purchase
  /// @param quantity Quantity of tokens to list
  function _createListing(
    address seller,
    address collection,
    uint256 tokenId,
    uint256 sellerPrice,
    uint256 buyerPrice,
    uint256 quantity
  ) internal {
    uint256 listingId = _nextListingId++;

    // Store the listing in the contract state
    listings[listingId] = Listing({
      seller: seller,
      collection: collection,
      tokenId: tokenId,
      quantity: quantity,
      sellerPrice: sellerPrice,
      buyerPrice: buyerPrice,
      active: true
    });

    emit ListingCreated(
      listingId,
      seller,
      collection,
      tokenId,
      sellerPrice,
      buyerPrice,
      quantity
    );
  }

  /// @notice Internal function to cancel an existing listing
  /// @dev Marks the listing as inactive
  function _cancelListing(address seller, uint256 listingId) internal {
    listings[listingId].active = false;
    emit ListingCancelled(listingId, seller);
  }

  /// @notice Internal function to purchase a listing
  /// @dev Updates quantity and emits relevant events; if fully purchased, marks the listing inactive
  function _buyListing(
    uint256 listingId,
    address buyer,
    uint256 quantity
  ) internal {
    Listing storage listing = listings[listingId];

    // Reduce the available quantity
    listing.quantity -= quantity;

    // If all tokens are purchased, deactivate listing and emit executed event
    if (listing.quantity == 0) {
      listing.active = false;
      emit ListingExecuted(listingId, buyer);
    }

    emit ListingPurchased(listingId, listing.seller, buyer);
  }
}
