// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {AggregatorV3Interface} from "@chainlink/contracts/src/v0.8/shared/interfaces/AggregatorV3Interface.sol";

/**
 * @title PriceFeed
 * @notice Fetches prices from Chainlink and computes token prices denominated in DAI.
 * @dev Example for PAXG/DAI or WBTC/DAI using Chainlink oracles.
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
    daiUsdFeed = AggregatorV3Interface(_daiUsdFeed);
    feedDecimals = _decimals;
  }

  /// @dev Internal helper to fetch latest price and normalize to 18 decimals
  function _getNormalizedPrice(
    AggregatorV3Interface feed
  ) internal view returns (uint256) {
    (, int256 price, , , ) = feed.latestRoundData();
    require(price > 0, "Invalid price");

    return uint256(price) * (10 ** (18 - feedDecimals)); // normalize to 18 decimals
  }

  /// @notice Returns PAXG price in DAI (scaled to 18 decimals)
  function getPaxgInDai() external view returns (uint256) {
    uint256 paxgUsd = _getNormalizedPrice(paxgUsdFeed);
    uint256 daiUsd = _getNormalizedPrice(daiUsdFeed);
    return (paxgUsd * 1e18) / daiUsd;
  }

  /// @notice Returns WBTC price in DAI (scaled to 18 decimals)
  function getWbtcInDai() external view returns (uint256) {
    uint256 wbtcUsd = _getNormalizedPrice(wbtcUsdFeed);
    uint256 daiUsd = _getNormalizedPrice(daiUsdFeed);
    return (wbtcUsd * 1e18) / daiUsd;
  }
}
