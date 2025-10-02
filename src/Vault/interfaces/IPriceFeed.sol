// SPDX-License-Identifier: MIT
pragma solidity ^0.8.7;

interface IPriceFeed {
    function getPaxgInDai() external view returns (uint256 price);
    function getWbtcInDai() external view returns (uint256 price);
}
