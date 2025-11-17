// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

contract MockVault {
    uint256 private price;

    constructor(uint256 _price) {
        price = _price;
    }

    function setPrice(uint256 _p) external {
        price = _p;
    }

    function getPrice() external view returns (uint256) {
        return price;
    }
}
