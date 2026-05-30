// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {OrderBookStorage} from "./BookStorage.sol";
import {IERC1155} from "@openzeppelin/contracts/token/ERC1155/IERC1155.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

/// @title TransferHelper
/// @notice Provides internal utility functions for handling NFT and ERC20 token transfers
/// @dev Inherits storage from OrderBookStorage
abstract contract TransferHelper is OrderBookStorage {
    using SafeERC20 for IERC20;

    /// @dev Supports ERC1155 standards
    function _handleNftTransferFrom(address from, address to, uint256 tokenId, uint256 quantity) internal {
        IERC1155(supportedCollection).safeTransferFrom(from, to, tokenId, quantity, "");
    }

    /// @notice Transfers ERC20 tokens from a sender to a recipient
    /// @dev Assumes `usdt` is an ERC20-compatible token stored in OrderBookStorage
    function _handleTokenTransferFrom(address from, address to, uint256 amount) internal {
        usdt.safeTransferFrom(from, to, amount);
    }

    /// @notice Transfers ERC20 tokens from this contract to a recipient
    function _handleTokenTransfer(address to, uint256 amount) internal {
        usdt.safeTransfer(to, amount);
    }

    /// @notice Approves a spender to transfer ERC20 tokens on behalf of this contract
    function _approveTokenTransfer(address spender, uint256 amount) internal {
        // reset to 0
        usdt.forceApprove(spender, 0);
        // set to desired amount
        usdt.forceApprove(spender, amount);
    }
}
