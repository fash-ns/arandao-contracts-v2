// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {OrderBookStorage} from "./OrderBookCore/BookStorage.sol";
import {ShareManager} from "./OrderBookCore/ShareManager.sol";
import {ListingManager} from "./OrderBookCore/ListingManager.sol";
import {OfferManager} from "./OrderBookCore/OfferManager.sol";
import {TransferHelper} from "./OrderBookCore/TransferHelper.sol";
import {ERC1155Holder} from "@openzeppelin/contracts/token/ERC1155/utils/ERC1155Holder.sol";
import {ValidationHelper} from "./OrderBookCore/ValidationHelper.sol";
import {ICoreContract} from "./OrderBookCore/interfaces/ICoreContract.sol";

/**
 * @title NFT OrderBook (ERC1155)
 * @notice Modular orderbook contract for ERC1155 NFT trading with integrated payout and referral logic.
 *
 * Core Features:
 *  - Sellers can list ERC1155 tokens for sale in exchange for a configured ERC20 token (e.g., DAI).
 *  - Buyers can purchase listed tokens directly; funds are split between seller, BV, and creator.
 *  - Buyers can place escrowed offers for ERC1155 tokens, which sellers can partially or fully accept.
 *  - Only whitelisted ERC1155 collections are supported.
 *  - All transactions are settled in the configured ERC20 payment token.
 *  - Integrates with an external Core contract to log orders and handle referral (parent) relationships.
 *
 * Design Notes:
 *  - When a buyer places an offer, their DAI is escrowed in this contract until accepted or canceled.
 *  - Listings do not lock NFTs; sellers simply approve this contract to transfer tokens upon purchase.
 *  - ERC1155 listings and offers can specify quantities greater than one.
 *  - Each transaction distributes DAI among:
 *      - Seller (seller share)
 *      - BV (business volume share)
 *      - Creator (royalty share)
 *  - The owner can register or remove supported collections.
 */
contract NFTOrderBook is
    Ownable,
    ReentrancyGuard,
    ERC1155Holder,
    OrderBookStorage,
    ShareManager,
    ListingManager,
    OfferManager,
    TransferHelper,
    ValidationHelper
{
    /// @notice Constructor to initialize the NFTOrderBook contract
    constructor(
        address initialOwner,
        address paymentToken,
        address coreContractAddress,
        uint256 minimumPrice,
        address collectionAddr
    ) Ownable(initialOwner) OrderBookStorage(paymentToken, coreContractAddress, minimumPrice, collectionAddr) {}

    /**
     * @notice List an NFT for sale
     * @param tokenId Token ID to list
     * @param sellerPrice Price per token seller wants (excludes fees)
     * @param quantity Number of NFTs to list
     * @dev Transfers NFT from seller to contract and creates a listing
     */
    function listTokenForSale(uint256 tokenId, uint256 sellerPrice, uint256 quantity) external nonReentrant {
        _validatePriceRange(sellerPrice);

        (,, uint256 buyerPrice) = _computeFromSeller(sellerPrice);
        address seller = msg.sender;

        _handleNftTransferFrom(seller, address(this), tokenId, quantity);
        _createListing(seller, tokenId, sellerPrice, buyerPrice, quantity);
    }

    /**
     * @notice Cancel an active listing
     * @param listingId ID of the listing to cancel
     * @dev Transfers NFT back to seller and marks listing as inactive
     */
    function cancelListForSale(uint256 listingId) external nonReentrant {
        Listing memory listing = listings[listingId];
        address caller = msg.sender;

        // validate caller is owner of listing and listing is active
        _onlyOwnerOfOrder(caller, listing.seller);
        _onlyActiveListing(listing.active);

        _cancelListing(caller, listingId);
        _handleNftTransferFrom(address(this), listing.seller, listing.tokenId, listing.quantity);
    }

    /**
     * @notice Buy an active listing
     * @param listingId ID of the listing to buy
     * @param quantity Quantity of NFTs to buy
     * @param parent Parent address for referral (if any)
     * @dev Transfers NFT to buyer and distributes USDT shares
     */
    function buyListing(uint256 listingId, uint256 quantity, address parent, uint8 position) external nonReentrant {
        _validateParentAndPosition(parent, position);

        Listing memory listing = listings[listingId];
        _onlyActiveListing(listing.active);
        _onlyValidQuantity(quantity, listing.quantity);

        address buyer = msg.sender;
        uint256 tbuyAmount = listing.buyerPrice * quantity;

        require(usdt.allowance(buyer, address(this)) >= tbuyAmount, "insufficient allowance");
        require(listing.seller != buyer, "cannot buy own listing");

        // Mark listing as inactive
        _buyListing(listingId, buyer, quantity);

        // Transfer USDT from buyer to Contract
        _handleTokenTransferFrom(buyer, address(this), tbuyAmount);

        (uint256 sellerAmount, uint256 bvAmount, uint256 creatorAmount) = _computeShares(listing.buyerPrice);
        _handleTokenTransfer(listing.seller, sellerAmount * quantity);
        _handleTokenTransfer(owner(), creatorAmount * quantity);

        // approve bv amount to core contract
        _approveTokenTransfer(coreContractAddress, bvAmount * quantity);

        ICoreContract.CreateOrderStruct[] memory orders = new ICoreContract.CreateOrderStruct[](1);
        orders[0] = ICoreContract.CreateOrderStruct({
            sellerAddress: listing.seller, sv: sellerAmount * quantity, bv: bvAmount * quantity
        });

        // Create order in Core Contract
        ICoreContract(coreContractAddress).createOrder(buyer, parent, position, orders, bvAmount * quantity);

        // Transfer NFT from contract to buyer
        _handleNftTransferFrom(address(this), buyer, listing.tokenId, quantity);
    }

    /**
     * @notice Place an offer for an NFT
     * @param tokenId Token ID to place offer on
     * @param quantity Quantity of NFTs to offer for
     * @param buyerPrice Price per token buyer is willing to pay
     * @param parent Parent address for referral (if any)
     * @dev Transfers USDT from buyer to contract and creates an offer
     */
    function placeOffer(uint256 tokenId, uint256 quantity, uint256 buyerPrice, address parent, uint8 position)
        external
        nonReentrant
    {
        _validatePriceRange(buyerPrice);
        _validateParentAndPosition(parent, position);

        address buyer = msg.sender;
        uint256 totalCost = buyerPrice * quantity;
        _handleTokenTransferFrom(buyer, address(this), totalCost);

        (uint256 sellerPrice,,) = _computeShares(buyerPrice);
        _createOffer(buyer, parent, position, tokenId, quantity, buyerPrice, sellerPrice);
    }

    /**
     * @notice Cancel an active offer
     * @param offerId ID of the offer to cancel
     * @dev Refunds USDT to buyer and marks offer as inactive
     */
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

    /**
     * @notice Accept an active offer
     * @param offerId ID of the offer to accept
     * @param quantity Quantity of NFTs to accept the offer for
     * @dev Transfers NFT from seller to buyer and distributes USDT shares
     */
    function acceptOffer(uint256 offerId, uint256 quantity) external nonReentrant {
        Offer memory offer = offers[offerId];
        _onlyValidQuantity(quantity, offer.quantity);

        address seller = msg.sender;
        require(offer.active, "offer not active");
        require(offer.buyer != seller, "cannot accept own offer");

        // Transfer NFT from seller to buyer
        _handleNftTransferFrom(seller, offer.buyer, offer.tokenId, quantity);

        // Mark offer as inactive
        _acceptOffer(offerId, seller, quantity);

        (uint256 sellerAmount, uint256 bvAmount, uint256 creatorAmount) = _computeShares(offer.buyerPrice);
        _handleTokenTransfer(owner(), creatorAmount * quantity);
        _handleTokenTransfer(seller, sellerAmount * quantity);

        _approveTokenTransfer(coreContractAddress, bvAmount * quantity);
        ICoreContract.CreateOrderStruct[] memory orders = new ICoreContract.CreateOrderStruct[](1);
        orders[0] = ICoreContract.CreateOrderStruct({
            sellerAddress: seller, sv: sellerAmount * quantity, bv: bvAmount * quantity
        });

        // Create order in Core Contract
        ICoreContract(coreContractAddress)
            .createOrder(offer.buyer, offer.parentAddress, offer.position, orders, bvAmount * quantity);
    }

    /// @notice Updates the supported NFT collection address
    function updateCollectionAddress(address collection) external onlyOwner {
        require(collection != address(0), "Invalid collection address");
        supportedCollection = collection;
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
