// SPDX-License-Identifier: MIT
// Compatible with OpenZeppelin Contracts ^5.4.0
pragma solidity ^0.8.30;

import {ERC1155} from "@openzeppelin/contracts/token/ERC1155/ERC1155.sol";
import {CollectionStorage} from "./CollectionStorage.sol";

abstract contract MintHelper is ERC1155, CollectionStorage {
    /// @dev Store a URI string for a specific token ID.
    function _setTokenURI(uint256 id, string calldata uri_) internal {
        _tokenURIs[id] = uri_;
    }

    /// @dev Batch-mint `ids`/`amounts` to `to`. Access is gated by the caller.
    function _mintTokenBatch(address to, uint256[] calldata ids, uint256[] calldata amounts) internal {
        require(ids.length == amounts.length, "Array lengths must match");
        _mintBatch(to, ids, amounts, "");
    }
}
