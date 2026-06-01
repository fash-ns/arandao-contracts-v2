// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

contract MockPriceFeed {
  function getPrice() public pure returns (uint256) {
    return 100 * 1e6;
  }
}
