// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

interface IYieldPool {
  function notifyReward(uint256 amount) external;
}
