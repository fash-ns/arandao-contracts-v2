// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

interface ITwapOracle {
    function getPrice() external view returns (uint256);
}
