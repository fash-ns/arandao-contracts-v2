// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

library BridgeLib {
  struct Stake {
    address userAddress;
    bool exists;
    uint256 totalPaidOut;
    bool principleWithdrawn;
  }

  function getMax(uint256 a, uint256 b) internal pure returns (uint256) {
    return a >= b ? a : b;
  }

  function getMin(uint256 a, uint256 b) internal pure returns (uint256) {
    return a >= b ? b : a;
  }
}
