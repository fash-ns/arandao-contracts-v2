// SPDX-License-Identifier: MIT
pragma solidity ^0.8.7;

import {AggregatorV3Interface} from "@chainlink/contracts/src/v0.8/interfaces/AggregatorV3Interface.sol";

/// @notice A very simple mock of Chainlink's AggregatorV3Interface for testing
contract MockV3Aggregator is AggregatorV3Interface {
    uint8 public override decimals;
    string public override description;
    uint256 public override version = 1;

    int256 private _answer;

    constructor(uint8 _decimals, int256 _initialAnswer) {
        decimals = _decimals;
        description = "MockV3Aggregator";
        _answer = _initialAnswer;
    }

    function updateAnswer(int256 _newAnswer) external {
        _answer = _newAnswer;
    }

    function latestRoundData()
        external
        view
        override
        returns (
            uint80 roundId,
            int256 answer,
            uint256 startedAt,
            uint256 updatedAt,
            uint80 answeredInRound
        )
    {
        return (0, _answer, 0, 0, 0);
    }

    // unused in our tests
    function getRoundData(uint80 _roundId)
        external
        view
        override
        returns (
            uint80 roundId,
            int256 answer,
            uint256 startedAt,
            uint256 updatedAt,
            uint80 answeredInRound
        )
    {
        return (_roundId, _answer, 0, 0, 0);
    }
}