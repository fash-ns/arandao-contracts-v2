// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {OrderBookStorage} from "./OrderBookCore/BookStorage.sol";
import {ShareManager} from "./OrderBookCore/ShareManager.sol";
import {ListingManager} from "./OrderBookCore/ListingManager.sol";
import {OfferManager} from "./OrderBookCore/OfferManager.sol";
import {Helper} from "./OrderBookCore/Helper.sol";
import {ERC721Holder} from "@openzeppelin/contracts/token/ERC721/utils/ERC721Holder.sol";
import {ERC1155Holder} from "@openzeppelin/contracts/token/ERC1155/utils/ERC1155Holder.sol";

/**
 * @title NFT OrderBook (ERC721 + ERC1155)
 * @author Sajad-Salehi
 * @notice Modular orderbook contract that supports:
 *  - Buyers creating offers (escrowed in USDT) for any whitelisted collection/token
 *  - Sellers accepting offers (transfer NFT -> buyer, pay seller in USDT)
 *  - Sellers listing NFTs for sale (buyers pay USDT and receive NFT)
 *  - Whitelisted collections only (with designated standard: ERC721 or ERC1155)
 *  - Payments only in a configured ERC20 (USDT) token
 *
 * Design notes:
 *  - Buyers' offers are escrowed on createOffer (USDT transferred to contract).
 *  - Listings are off-chain/approval-based: seller must approve this contract to transfer
 *    their NFT when a buyer calls buyListing. This avoids locking NFTs in contract.
 *  - ERC1155 supports multi-quantity listings/offers; ERC721 amount is always 1.
 *  - Platform fee (bps) is configurable by owner; fee is deducted on successful sale
 *    and kept in contract until owner withdraws.
 */
contract NFTOrderBook is
  Ownable,
  ReentrancyGuard,
  ERC721Holder,
  ERC1155Holder,
  OrderBookStorage,
  ShareManager,
  ListingManager,
  OfferManager,
  Helper
{
  /// @notice Ensures that the collection is whitelisted and quantity is valid
  modifier onlyValidCollection(address collection, uint256 quantity) {
    _checkCollection(collection, quantity);
    _;
  }

  /// @notice Constructor to initialize the NFTOrderBook contract
  constructor(
    address initialOwner,
    address _usdtToken,
    address _bvRecipient,
    address _feeRecipient,
    uint256 _denom,
    uint256 _sellerNum,
    uint256 _bvNum,
    uint256 _minimumPrice
  )
    Ownable(initialOwner)
    OrderBookStorage(
      _usdtToken,
      _bvRecipient,
      _feeRecipient,
      _denom,
      _sellerNum,
      _bvNum,
      _minimumPrice
    )
  {}

  /// @notice List an NFT for sale
  /// @param collection NFT contract address
  /// @param tokenId Token ID to list
  /// @param sellerPrice Price requested by the seller
  /// @param quantity Quantity of NFTs (1 for ERC721)
  /// @dev Transfers NFT from seller to contract (escrow) and emits ListingCreated
  function listTokenForSale(
    address collection,
    uint256 tokenId,
    uint256 sellerPrice,
    uint256 quantity
  ) external onlyValidCollection(collection, quantity) nonReentrant {
    require(sellerPrice >= _minPrice, "price must be >= minimum amount");

    (, , uint256 buyerPrice) = _computeFromSeller(sellerPrice);
    address seller = msg.sender;

    _handleNftTransferFrom(
      seller,
      address(this),
      collection,
      tokenId,
      quantity
    );
    _createListing(
      seller,
      collection,
      tokenId,
      sellerPrice,
      buyerPrice,
      quantity
    );
  }

  /// @notice Cancel an active listing and return NFT to seller
  /// @param listingId ID of the listing to cancel
  function cancelListForSale(uint256 listingId) external nonReentrant {
    Listing memory listing = listings[listingId];
    address caller = msg.sender;

    require(listing.active, "listing not active");
    require(listing.seller == caller, "not listing owner");

    _cancelListing(caller, listingId);
    _handleNftTransferFrom(
      address(this),
      listing.seller,
      listing.collection,
      listing.tokenId,
      listing.quantity
    );
  }

  /// @notice Buy an NFT from an active listing
  /// @param listingId ID of the listing
  /// @param quantity Number of NFTs to buy
  /// @dev Transfers USDT from buyer, distributes shares, and transfers NFT to buyer
  function buyListing(
    uint256 listingId,
    uint256 quantity,
    address parent
  ) external nonReentrant {
    require(parent != address(0), "Invalid parent address");

    Listing memory listing = listings[listingId];
    require(quantity > 0 && quantity <= listing.quantity, "invalid quantity");

    address buyer = msg.sender;
    uint256 tbuyAmount = listing.buyerPrice * quantity;
    require(
      usdt.allowance(buyer, address(this)) >= tbuyAmount,
      "insufficient allowance"
    );

    require(listing.active, "listing not active");
    require(listing.seller != buyer, "cannot buy own listing");

    // Mark listing as inactive
    _buyListing(listingId, buyer, quantity);

    // Transfer USDT from buyer to Contract (**should change to entry point**)
    _handleTokenTransferFrom(buyer, address(this), tbuyAmount);

    // Distribute USDT to BV and fee recipient
    // Todo *** pass shares and associated addresses to entry point for distribution ***
    // Todo pass parent address from input to entrypoint contract
    (
      uint256 sellerAmount,
      uint256 bvAmount,
      uint256 creatorAmount
    ) = _computeShares(listing.buyerPrice);
    _handleTokenTransfer(listing.seller, sellerAmount * quantity);
    _handleTokenTransfer(bvRecipient, bvAmount * quantity);
    _handleTokenTransfer(feeRecipient, creatorAmount * quantity);

    // Transfer NFT from contract to buyer
    _handleNftTransferFrom(
      address(this),
      buyer,
      listing.collection,
      listing.tokenId,
      quantity
    );
  }

  /// @notice Place an offer for an NFT
  /// @param collection NFT contract address
  /// @param tokenId Token ID to buy
  /// @param quantity Quantity requested
  /// @param buyerPrice Price per token buyer is willing to pay (includes fees)
  /// @dev Escrows USDT on offer creation
  function placeOffer(
    address collection,
    uint256 tokenId,
    uint256 quantity,
    uint256 buyerPrice,
    address parent
  ) external onlyValidCollection(collection, quantity) nonReentrant {
    require(buyerPrice > _minPrice, "price must be >= minimum amount");

    address buyer = msg.sender;

    // Compute total cost and transfer USDT from buyer to contract
    uint256 totalCost = buyerPrice * quantity;
    _handleTokenTransferFrom(buyer, address(this), totalCost);

    (, , uint256 sellerPrice) = _computeShares(buyerPrice);
    _createOffer(
      buyer,
      parent,
      collection,
      tokenId,
      quantity,
      buyerPrice,
      sellerPrice
    );
  }

  /// @notice Cancel an active offer and refund the buyer
  /// @param offerId ID of the offer to cancel
  function cancelOffer(uint256 offerId) external nonReentrant {
    Offer memory offer = offers[offerId];
    address caller = msg.sender;

    require(offer.active, "offer not active");
    require(offer.buyer == caller, "not offer owner");

    // Mark offer as inactive
    _cancelOffer(offerId, caller);

    // Refund USDT to buyer
    uint256 refundAmount = offer.buyerPrice * offer.quantity;
    _handleTokenTransfer(offer.buyer, refundAmount);
  }

  /// @notice Accept an active offer as a seller
  /// @param offerId ID of the offer
  /// @param quantity Quantity of NFTs to sell
  /// @dev Transfers NFT to buyer and distributes USDT shares
  function acceptOffer(
    uint256 offerId,
    uint256 quantity
  ) external nonReentrant {
    Offer memory offer = offers[offerId];
    require(quantity > 0 && quantity <= offer.quantity, "invalid quantity");

    address seller = msg.sender;
    require(offer.active, "offer not active");
    require(offer.buyer != seller, "cannot accept own offer");

    // Transfer NFT from seller to buyer
    _handleNftTransferFrom(
      seller,
      offer.buyer,
      offer.collection,
      offer.tokenId,
      quantity
    );

    // Mark offer as inactive
    _acceptOffer(offerId, seller, quantity);

    // Distribute USDT to seller, BV and fee recipient
    // Todo *** pass shares and associated addresses to entry point for distribution ***
    // Todo pass the parent address to entrypoint (parents[buyer])
    (
      uint256 bvAmount,
      uint256 creatorAmount,
      uint256 sellerAmount
    ) = _computeShares(offer.buyerPrice);
    _handleTokenTransfer(bvRecipient, bvAmount * quantity);
    _handleTokenTransfer(feeRecipient, creatorAmount * quantity);
    _handleTokenTransfer(seller, sellerAmount * quantity);
  }

  function registerCollection(
    address collection,
    uint8 typeNum
  ) external onlyOwner {
    collections[collection] = CollectionInfo(TokenType(typeNum), true);
  }

  function removeCollection(address collection) external onlyOwner {
    collections[collection].exists = false;
  }

  /// @notice Transfers contract ownership to a new address, but only once.
  /// @dev Uses `ownershipFlag` to ensure ownership can only be transferred a single time.
  function transferOwnership(address newOwner) public override onlyOwner {
    if (ownershipFlag == false) {
      super.transferOwnership(newOwner);
      ownershipFlag = true;
    } else {
      revert("Ownership has already been transferred");
    }
  }
}
