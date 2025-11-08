// SPDX-License-Identifier: MIT
// Compatible with OpenZeppelin Contracts ^5.4.0
pragma solidity ^0.8.28;

import {ERC1155} from "@openzeppelin/contracts/token/ERC1155/ERC1155.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {CollectionStorage} from "./CollectionStorage.sol";

abstract contract MintHelper is Ownable, ERC1155, CollectionStorage {
  /// @dev Validate that the mint conditions are met for the given tokenId.
  function _validateMint() internal view {
    require(isInitialMintEnable, "Mint is not enable");
  }

  /// @notice Owner sets the URI for a specific token ID.
  function _setTokenURI(uint256 id, string calldata uri) internal {
    _tokenURIs[id] = uri;
  }

  /// @notice Owner mints multiple token ids to a recipient in a single transaction.
  function _mintTokenBatch(
    address to,
    uint256[] calldata ids,
    uint256[] calldata amounts
  ) internal {
    _validateMint();

    uint256 length = ids.length;
    require(
      length == ids.length && length == amounts.length,
      "Array lengths must match"
    );
    _mintBatch(to, ids, amounts, "");
  }

  function _disableInitialMint() internal {
    isInitialMintEnable = false;
  }
}
