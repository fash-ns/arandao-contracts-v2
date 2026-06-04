// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

/**
 * @title DexErrors
 * @dev Custom errors for gas-efficient error handling.
 */
library DexErrors {
  error ZeroAddress();
  error SameTokens();
  error Unauthorized();
  error InvalidAmounts();
  error OrderNotActive();
  error OrderNotFound();
  error CannotFillOwnOrder();
  error InsufficientOrderAmount();
  error FeeReceiverAlreadyChanged();
}
