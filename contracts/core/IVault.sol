// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

interface IVault {
  function deposit(uint256 amountToDeposit) external;
  function withdrawDai(uint256 amount) external;
  function getPrice() external view returns (uint256);
}
