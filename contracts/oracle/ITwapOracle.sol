// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

/// @title ITwapOracle
/// @notice Interface for the TWAP oracle price feed and keeper-driven updates.
/// @dev    Implemented by TwapOracle.  Returns FIXED_PRICE during Phase 1 (before
///         activateTwap is called) and the live Uniswap V2 TWAP price during Phase 2.
///         Callers should treat the returned value as quoteToken base units per one
///         full token — e.g. 300_000_000 means 300 USDT when quoteToken has 6 decimals.
interface ITwapOracle {
    /// @notice Returns the current price of one full token in quoteToken base units.
    /// @return price  Phase-1: the fixed seed price.  Phase-2: the TWAP price derived
    ///                from the Uniswap V2 pool.  Never returns zero.
    function getPrice() external view returns (uint256 price);

    /// @notice Advances the TWAP snapshot. Only callable by the configured keeper.
    function update() external;

    /// @notice Returns true when PERIOD has elapsed and update() may be called.
    function updateReady() external view returns (bool);
}
