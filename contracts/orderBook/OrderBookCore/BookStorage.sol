// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {Initializable} from "@openzeppelin/contracts/proxy/utils/Initializable.sol";

/// @title Abstract Storage for an Order Book Marketplace
/// @notice Stores all essential state variables and structures for listings and offers of ERC721/ERC1155 tokens
abstract contract OrderBookStorage is Initializable {
  /// @notice ERC20 token used for payments (e.g., USDT stablecoin)
  IERC20 internal usdt;

  // Fraction constants used for fee distribution (numerator / DENOM)
  uint256 internal constant DENOM = 150; // Denominator for fractional calculations
  uint256 internal constant SELLER_NUM = 50; // Seller's fraction numerator (e.g., 50 / 150)
  uint256 internal constant BV_NUM = 100; // BV's fraction numerator (e.g., 100 / 150)

  // Creator takes 27% of BV
  uint256 internal constant CREATOR_FEE_BPS = 2700;

  /// @notice ID for new listings and offers
  uint256 internal _nextListingId;
  uint256 internal _nextOfferId;

  // @notice min price
  uint256 internal _minPrice;

  /// @notice 73% of BV goes to this core contract address
  address public coreContractAddress;

  /// @notice Flag indicating if ownership transfer has occurred
  bool public ownershipFlag;

  /// @notice Deadline timestamp after which upgrades are no longer allowed
  uint256 public upgradeDeadline;

  /// @notice Represents an NFT listed for sale
  struct Listing {
    address seller; // Owner of the NFT
    uint256 tokenId; // Token ID of the NFT
    uint256 quantity; // Number of tokens listed (1 for ERC721)
    uint256 sellerPrice; // Listing price in USDT
    uint256 buyerPrice; // Price if bought via "Buy Now" option
    bool active; // True if listing is currently active
  }

  /// @notice Represents an offer made by a buyer on a listed NFT
  struct Offer {
    address buyer; // Buyer address
    uint256 tokenId; // Token ID of the NFT
    uint256 quantity; // Amount buyer wants to purchase
    uint256 sellerPrice; // Listing price in USDT
    uint256 buyerPrice; // Price if bought via "Buy Now" option
    address parentAddress; // Parent address for referral
    uint8 position; // Position of the listing in the order book
    bool active; // True if offer is currently active
  }

  /// @notice Supported NFT collection address
  address public supportedCollection;

  /// @notice Mapping from listing ID to Listing struct
  mapping(uint256 => Listing) public listings;

  /// @notice Mapping from offer ID to Offer struct
  mapping(uint256 => Offer) public offers;

  /// @notice Constructor initializes core parameters and fee distribution numerators
  function __OrderBookStorage_init(
    address _paymentToken,
    address _coreContractAddress,
    address _supportedCollection
  ) internal onlyInitializing {
    require(_paymentToken != address(0), "paymentToken zero");
    require(_coreContractAddress != address(0), "coreContractAddress zero");
    require(_supportedCollection != address(0), "supportedCollection zero");

    supportedCollection = _supportedCollection;
    usdt = IERC20(_paymentToken);
    coreContractAddress = _coreContractAddress;
    _minPrice = 100e18; // 100DAI
    upgradeDeadline = block.timestamp + 90 days;

    _nextListingId = 1; // Start listing IDs from 1
    _nextOfferId = 1; // Start offer IDs from 1
  }
}
