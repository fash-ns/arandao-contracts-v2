// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {OrderBookStorage} from "./BookStorage.sol";

/**
 * @title Validation Helper
 * @notice Provides validation functions for the OrderBook contract
 */
abstract contract ValidationHelper is OrderBookStorage {
    /**
     * @notice Validates that the parent address and position are valid
     */
    function _validateParentAndPosition(address parent, uint256 position) internal pure {
        require(parent != address(0), "Invalid parent address");
        require(position <= 3, "Invalid position");
    }

    /**
     * @notice Validates that the price is within the acceptable range
     */
    function _validatePriceRange(uint256 price) internal view {
        require(price >= _minPrice, "Price below minimum");
    }

    /**
     * @notice Validates that the listing is active
     */
    function _onlyActiveListing(bool listingActive) internal pure {
        require(listingActive, "listing not active");
    }

    /**
     * @notice Validates that the caller is the owner of the listing / order
     */
    function _onlyOwnerOfOrder(address caller, address ownerOfOrder) internal pure {
        require(caller == ownerOfOrder, "not listing owner");
    }

    /**
     * @notice Validates the requested quantity against the available quantity
     */
    function _onlyValidQuantity(uint256 quantity, uint256 availableQuantity) internal pure {
        require(quantity > 0 && quantity <= availableQuantity, "invalid quantity");
    }
}
