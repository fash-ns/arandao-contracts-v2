// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {OrderBookStorage} from "./BookStorage.sol";

/// @title OfferManager
/// @notice Manages offers/Orders in the OrderBook, including creation, cancellation, and acceptance.
abstract contract OfferManager is OrderBookStorage {
  /// @notice Emitted when a new offer is created
  event OfferCreated(
    uint256 indexed id,
    address indexed buyer,
    address collection,
    uint256 tokenId,
    uint256 quantity,
    uint256 price
  );

  /// @notice Emitted when an offer is cancelled
  event OfferCancelled(uint256 indexed id, address indexed buyer);

  /// @notice Emitted when an offer is accepted (partially or fully)
  event OfferAccepted(
    uint256 indexed id,
    address indexed buyer,
    address seller,
    uint256 tokenId,
    uint256 quantity
  );

  /// @notice Emitted when an offer is fully executed (all quantity accepted)
  event OfferExecuted(uint256 indexed id, address indexed buyer);

  /// @notice Internal function to create a new offer
  function _createOffer(
    address buyer,
    address parent,
    uint8 position,
    uint256 tokenId,
    uint256 quantity,
    uint256 buyerPrice,
    uint256 sellerPrice
  ) internal {
    uint256 offerId = _nextOfferId++;
    offers[offerId] = Offer({
      buyer: buyer,
      tokenId: tokenId,
      quantity: quantity,
      sellerPrice: sellerPrice,
      buyerPrice: buyerPrice,
      parentAddress: parent,
      position: position,
      active: true
    });
    emit OfferCreated(
      offerId,
      buyer,
      supportedCollection,
      tokenId,
      quantity,
      buyerPrice
    );
  }

  /// @notice Internal function to cancel an existing offer
  function _cancelOffer(uint256 offerId, address caller) internal {
    offers[offerId].active = false;
    emit OfferCancelled(offerId, caller);
  }

  /// @notice Internal function to accept an offer
  /// @dev Updates quantity, and deactivates offer if fully executed
  function _acceptOffer(
    uint256 offerId,
    address seller,
    uint256 tokenId,
    uint256 quantity
  ) internal {
    Offer storage offer = offers[offerId];
    offer.quantity -= quantity;
    address buyer = offer.buyer;

    // Deactivate offer if fully executed
    if (offer.quantity == 0) {
      offer.active = false;
      emit OfferExecuted(offerId, buyer);
    }

    emit OfferAccepted(offerId, buyer, seller, tokenId, quantity);
  }
}
