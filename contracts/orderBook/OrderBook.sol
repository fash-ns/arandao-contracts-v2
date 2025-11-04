// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {OrderBookStorage} from "./OrderBookCore/BookStorage.sol";
import {ShareManager} from "./OrderBookCore/ShareManager.sol";
import {ListingManager} from "./OrderBookCore/ListingManager.sol";
import {OfferManager} from "./OrderBookCore/OfferManager.sol";
import {TransferHelper} from "./OrderBookCore/TransferHelper.sol";
import {ERC1155Holder} from "@openzeppelin/contracts/token/ERC1155/utils/ERC1155Holder.sol";
import {ValidationHelper} from "./OrderBookCore/ValidationHelper.sol";
import {ICoreContract} from "./OrderBookCore/interfaces/ICoreContract.sol";
import {ICollection} from "./OrderBookCore/interfaces/ICollection.sol";

/**
 * @title NFT OrderBook (ERC1155)
 * @notice Modular ERC1155 marketplace contract supporting listings, offers, and integrated referral tracking.
 *
 * @dev This contract enables decentralized trading of ERC1155 NFTs using a configured ERC20 token (e.g., DAI).
 * It provides both seller-driven listings and buyer-driven offers, with automatic share distribution to
 * sellers, business volume (BV) accounts, and creators. All accounting and referral data is logged through
 * an external Core contract, ensuring modularity and scalability.
 *
 * Core Features:
 *  - **Listing NFTs:** Sellers can list ERC1155 tokens at a chosen price. Buyers purchase directly with DAI.
 *  - **Buying Listings:** Buyers pay DAI to purchase listed NFTs; funds are split between seller, BV, and creator.
 *  - **Offers:** Buyers can place escrowed offers on NFTs. Sellers can accept offers fully or partially.
 *  - **Collection Management:** Only a single whitelisted ERC1155 collection is supported at a time (configurable by owner).
 *  - **Referral Integration:** Every trade supports an optional parent address and position for referral tracking,
 *    which are passed to the external Core contract via `createOrder`.
 *  - **Token Settlements:** All payments and escrow operations use the configured ERC20 token.
 */
contract NFTOrderBook is
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
        address paymentToken,
        address coreContractAddress,
        address collectionAddr
    ) OrderBookStorage(paymentToken, coreContractAddress, collectionAddr) {}

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

        // transfer to collection owner
        _handleCreatorPayout(creatorAmount, quantity);

        // approve bv amount to core contract
        _approveTokenTransfer(coreContractAddress, bvAmount * quantity);

        ICoreContract.CreateOrderStruct[] memory orders = new ICoreContract.CreateOrderStruct[](1);
        orders[0] = ICoreContract.CreateOrderStruct({
            sellerAddress: _getCollectionOwner(), sv: sellerAmount * quantity, bv: bvAmount * quantity
        });

        try ICoreContract(coreContractAddress).createOrder(
            buyer, 
            parent, 
            position, 
            orders, 
            bvAmount * quantity
        ) {
        } catch {
            revert("Core contract failed, cannot complete order");
        }

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
        
        // transfer to collection owner
        _handleCreatorPayout(creatorAmount, quantity);
        
        _handleTokenTransfer(seller, sellerAmount * quantity);

        _approveTokenTransfer(coreContractAddress, bvAmount * quantity);
        ICoreContract.CreateOrderStruct[] memory orders = new ICoreContract.CreateOrderStruct[](1);
        orders[0] = ICoreContract.CreateOrderStruct({
            sellerAddress: _getCollectionOwner(), sv: sellerAmount * quantity, bv: bvAmount * quantity
        });

        try ICoreContract(coreContractAddress).createOrder(
            offer.buyer, 
            offer.parentAddress, 
            offer.position, 
            orders, 
            bvAmount * quantity
        ) {
        } catch {
            revert("Core contract failed, cannot complete order");
        }
    }


    /**
     * @dev Handles transferring creator fees to the collection owner.
     * @param creatorAmount The amount to transfer per token.
     * @param quantity The number of tokens involved in the transfer.
     */
    function _handleCreatorPayout(
        uint256 creatorAmount,
        uint256 quantity
    ) internal {
        address collectionOwner = _getCollectionOwner();
        require(collectionOwner != address(0), "Invalid collection owner");

        uint256 totalAmount = creatorAmount * quantity;
        _handleTokenTransfer(collectionOwner, totalAmount);
    }

    function _getCollectionOwner() internal view returns (address) {
        return ICollection(supportedCollection).owner();
    }
}
