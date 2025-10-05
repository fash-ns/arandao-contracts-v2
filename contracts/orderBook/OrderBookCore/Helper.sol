// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import {OrderBookStorage} from "./BookStorage.sol";
import {IERC721} from "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import {IERC1155} from "@openzeppelin/contracts/token/ERC1155/IERC1155.sol";

/// @title Helper
/// @notice Provides internal utility functions for handling NFT and ERC20 token transfers, and collection validation.
/// @dev Inherits storage from OrderBookStorage
abstract contract Helper is OrderBookStorage {
  /// @notice Transfers an NFT from one address to another
  /// @dev Supports both ERC721 and ERC1155 standards
  function _handleNftTransferFrom(
    address from,
    address to,
    address collection,
    uint256 tokenId,
    uint256 quantity
  ) internal {
    TokenType tokenType = collections[collection].tokenType;

    if (tokenType == TokenType.ERC721) {
      // ERC721 supports only single token transfers
      IERC721(collection).safeTransferFrom(from, to, tokenId);
    } else if (tokenType == TokenType.ERC1155) {
      // ERC1155 supports batch/multiple token transfers
      IERC1155(collection).safeTransferFrom(from, to, tokenId, quantity, "");
    }
  }

  /// @notice Transfers ERC20 tokens from a sender to a recipient
  /// @dev Assumes `usdt` is an ERC20-compatible token stored in OrderBookStorage
  function _handleTokenTransferFrom(
    address from,
    address to,
    uint256 amount
  ) internal {
    bool isSuccess = dai.transferFrom(from, to, amount);
    require(isSuccess, "Token transfer failed");
  }

  /// @notice Transfers ERC20 tokens from this contract to a recipient
  function _handleTokenTransfer(address to, uint256 amount) internal {
    bool isSuccess = dai.transfer(to, amount);
    require(isSuccess, "Token transfer failed");
  }

  /// @notice Validates that a collection is whitelisted and that the quantity is valid
  function _checkCollection(
    address collection,
    uint256 quantity
  ) internal view {
    CollectionInfo memory info = collections[collection];
    require(info.exists, "collection not whitelisted");

    if (info.tokenType == TokenType.ERC721) {
      require(quantity == 1, "ERC721 quantity must be 1");
    } else if (info.tokenType == TokenType.ERC1155) {
      require(quantity > 0, "ERC1155 quantity must be greater than 0");
    }
  }
}
