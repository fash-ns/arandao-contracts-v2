// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

/// @dev Minimal TwapOracle stand-in for OracleKeeper unit tests.
contract MockTwapOracle {
    uint256 public updateCount;
    bool public ready = true;

    function update() external {
        updateCount += 1;
    }

    function updateReady() external view returns (bool) {
        return ready;
    }

    function setReady(bool value) external {
        ready = value;
    }
}
