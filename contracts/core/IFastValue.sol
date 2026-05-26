// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

interface IFastValue {
  function addMonthlyFv(uint256 month, uint256 amount) external;

  function getUserShare(
    uint256 userId,
    uint256 month
  ) external view returns (uint8);

  function submitUserForFastValue(
    uint256 userId,
    uint256 month,
    uint8 share
  ) external;
}
