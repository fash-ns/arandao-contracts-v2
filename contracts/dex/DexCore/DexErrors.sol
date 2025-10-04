// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

/**
 * @title DexErrors
 * @dev Custom errors for gas-efficient error handling.
 */
library DexErrors {
  error ZeroAddress();
  error SameTokens();
  error FeeTooHigh();
  error Unauthorized();
  error InvalidTierConfiguration();
  error InvalidAmounts();
  error OrderNotActive();
  error OrderNotFound();
  error InvalidFillAmount();
  error FillExceedsRemaining();
  error CannotFillOwnOrder();
  error NotOrderMaker();
  error InvalidOrder(uint256 id);
  error AmountMustBePositive();
  error PriceMustBePositive();
  error PriceOutOfRange();
}
