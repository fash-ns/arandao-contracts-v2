// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

interface ICore {
  function getUserIdByAddress(
    address userAddress
  ) external view returns (uint256);

  function getCurrentMonthNo() external view returns (uint256);
}
