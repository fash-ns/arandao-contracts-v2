// SPDX-License-Identifier: MIT
// Compatible with OpenZeppelin Contracts ^5.4.0
pragma solidity ^0.8.30;

import {ERC1155} from "@openzeppelin/contracts/token/ERC1155/ERC1155.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {CollectionStorage} from "./CollectionStorage.sol";

abstract contract MintHelper is Ownable, ERC1155, CollectionStorage {
    /// @dev Validate that the mint conditions are met for the given tokenId.
    function _validateMint(uint256 id) internal pure {
        require(id <= MAX_TOKEN_ID, "invalid token id");
    }

    /// @notice Owner sets the URI for a specific token ID.
    function _setTokenURI(uint256 id, string calldata uri) internal {
        _tokenURIs[id] = uri;
    }

    /// @notice Owner mints a single token id (used for initial issuance or any owner mint).
    function _mintToken(address account, uint256 id, uint256 amount, string calldata uri) internal {
        _validateMint(id);
        _mint(account, id, amount, "");
        _setTokenURI(id, uri);
    }

    /// @notice Owner mints multiple token ids to multiple recipients in a single transaction.
    function _mintTokenBatch(address[] calldata recipients, uint256[] calldata ids, uint256[] calldata amounts)
        internal
    {
        uint256 length = recipients.length;

        require(length == ids.length && length == amounts.length, "Array lengths must match");
        require(length > 0 && length <= 50, "Invalid batch size");

        for (uint256 i = 0; i < length; i++) {
            _mintToken(recipients[i], ids[i], amounts[i], uris[i]);
        }
    }
}

