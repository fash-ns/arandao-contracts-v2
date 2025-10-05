// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

interface IMultiAssetVault {
  function deposit(uint256 amountToDeposit) external;
  function getPrice() external view returns (uint256);
  function withrawDai(uint256 amount) external;
}
