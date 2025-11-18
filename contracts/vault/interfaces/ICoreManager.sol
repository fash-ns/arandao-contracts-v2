// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

interface ICoreManager {
    function isManager(address) external view returns (bool);
}
