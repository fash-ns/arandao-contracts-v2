// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

/// @title Abstract Storage for an Order Book Marketplace
/// @notice Stores all essential state variables and structures for listings and offers of ERC721/ERC1155 tokens
abstract contract OrderBookStorage {
  /// @notice ERC20 token used for payments (e.g., dai stablecoin)
  IERC20 internal dai;

  // Fraction constants used for fee distribution (numerator / DENOM)
  uint256 internal immutable DENOM; // Denominator for fractional calculations (e.g., 167)
  uint256 internal immutable SELLER_NUM; // Seller's fraction numerator (e.g., 50 / 167)
  uint256 internal immutable BV_NUM; // BV's fraction numerator (e.g., 100 / 167)

  /// @notice ID for new listings and offers
  uint256 internal _nextListingId;
  uint256 internal _nextOfferId;

  // @notice min price
  uint256 internal _minPrice;

  /// @notice Address receiving BV portion of payments and platform fees
  address public bvRecipient;
  address public feeRecipient;

  /// @notice Flag to allow ownership transfer only once.
  bool public ownershipFlag;

  /// @notice Supported token types in marketplace
  enum TokenType {
    ERC721,
    ERC1155
  }

  /// @notice Metadata for supported collections
  struct CollectionInfo {
    TokenType tokenType;
    bool exists; // True if the collection is supported
  }

  /// @notice Represents an NFT listed for sale
  struct Listing {
    address seller; // Owner of the NFT
    address collection; // NFT collection contract address
    uint256 tokenId; // Token ID of the NFT
    uint256 quantity; // Number of tokens listed (1 for ERC721)
    uint256 sellerPrice; // Listing price in dai
    uint256 buyerPrice; // Price if bought via "Buy Now" option
    bool active; // True if listing is currently active
  }

  /// @notice Represents an offer made by a buyer on a listed NFT
  struct Offer {
    address buyer; // Buyer address
    address collection; // NFT collection contract address
    uint256 tokenId; // Token ID of the NFT
    uint256 quantity; // Amount buyer wants to purchase
    uint256 sellerPrice; // Listing price in dai
    uint256 buyerPrice; // Price if bought via "Buy Now" option
    bool active; // True if offer is currently active
  }

  /// @notice Mapping of supported NFT collections
  mapping(address => CollectionInfo) public collections;

  /// @notice Mapping from listing ID to Listing struct
  mapping(uint256 => Listing) public listings;

  /// @notice Mapping from offer ID to Offer struct
  mapping(uint256 => Offer) public offers;

  /// @notice parent addresses
  mapping(address => address) public parents;

  /// @notice Constructor initializes core parameters and fee distribution numerators
  constructor(
    address _daiToken,
    address _bvRecipient,
    address _feeRecipient,
    uint256 _denom,
    uint256 _sellerNum,
    uint256 _bvNum,
    uint256 _minimumPrice
  ) {
    require(_daiToken != address(0), "dai zero");
    require(_bvRecipient != address(0), "bvRecipient zero");
    require(_feeRecipient != address(0), "feeRecipient zero");
    require(_denom != 0, "DENOM zero");

    dai = IERC20(_daiToken);
    feeRecipient = _feeRecipient;
    bvRecipient = _bvRecipient;

    DENOM = _denom;
    SELLER_NUM = _sellerNum;
    BV_NUM = _bvNum;

    _minPrice = _minimumPrice;

    _nextListingId = 1; // Start listing IDs from 1
    _nextOfferId = 1; // Start offer IDs from 1
  }
}
