// SPDX-License-Identifier: MIT
pragma solidity ^0.8.7;

import {AggregatorV3Interface} from "@chainlink/contracts/src/v0.8/interfaces/AggregatorV3Interface.sol";

/**
 * @title PriceFeed
 * @notice Fetches prices from Chainlink and computes token prices denominated in DAI.
 * @dev Example for PAXG/DAI or WBTC/DAI using Chainlink oracles.
 * @dev This contract is for demonstration purposes and is NOT audited.
 */
contract PriceFeed {
    AggregatorV3Interface internal paxgUsdFeed;
    AggregatorV3Interface internal wbtcUsdFeed;
    AggregatorV3Interface internal daiUsdFeed;
    uint8 feedDecimals;

    constructor(
        address _paxgUsdFeed,
        address _wbtcUsdFeed,
        address _daiUsdFeed, 
        uint8 _decimals
    ) {
        paxgUsdFeed = AggregatorV3Interface(_paxgUsdFeed);
        wbtcUsdFeed = AggregatorV3Interface(_wbtcUsdFeed);
        daiUsdFeed  = AggregatorV3Interface(_daiUsdFeed);
        feedDecimals = _decimals;

        /**
         * Example feed addresses (Sepolia / Ethereum mainnet):
         * - PAXG / USD: 0x0f6914d8e7e1214CDb3A4C6fbf729b75C69DF608
         * - WBTC / USD: 0xDE31F8bFBD8c84b5360CFACCa3539B938dd78ae6
         * - DAI  / USD: 0x4746DeC9e833A82EC7C2C1356372CcF2cfcD2F3D
         */
    }

    /// @dev Internal helper to fetch latest price and normalize to 18 decimals
    function _getNormalizedPrice(AggregatorV3Interface feed) internal view returns (uint256) {
        (
            , 
            int256 price,
            ,
            ,
            
        ) = feed.latestRoundData();
        require(price > 0, "Invalid price");

        return uint256(price) * (10 ** (18 - feedDecimals)); // normalize to 18 decimals
    }

    /// @notice Returns PAXG price in DAI (scaled to 18 decimals)
    function getPaxgInDai() external view returns (uint256) {
        uint256 paxgUsd = _getNormalizedPrice(paxgUsdFeed);
        uint256 daiUsd  = _getNormalizedPrice(daiUsdFeed);
        return (paxgUsd * 1e18) / daiUsd;
    }

    /// @notice Returns WBTC price in DAI (scaled to 18 decimals)
    function getWbtcInDai() external view returns (uint256) {
        uint256 wbtcUsd = _getNormalizedPrice(wbtcUsdFeed);
        uint256 daiUsd  = _getNormalizedPrice(daiUsdFeed);
        return (wbtcUsd * 1e18) / daiUsd;
    }
}