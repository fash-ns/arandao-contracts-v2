// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import {IUniswapV2Router02} from "@uniswap/v2-periphery/contracts/interfaces/IUniswapV2Router02.sol";

abstract contract VaultStorage {

    // Token Addresses
    address public immutable DAI;
    address public immutable PAXG;
    address public immutable WBTC;
    address public immutable DNM;

    // Asset Allocation Percentages (out of 100)
    uint256 public immutable ALLOCATION_PAXG; 
    uint256 public immutable ALLOCATION_WBTC; 
    uint256 public immutable ALLOCATION_DAI; 
    uint256 public immutable WITHDRAWAL_DELAY;

    /// @dev The maximum accepted slippage for swaps E.g., 50 = 0.5%.
    uint256 internal _slippageBps;
    /// @dev The denominator used for slippage calculation
    uint256 internal _slippageDenominator;

    /// @dev The duration (in seconds) added to block.timestamp to set the swap transaction deadline.
    uint256 internal _deadlineDuration;

    /// @dev The Uniswap V2 Router contract interface used for executing all swaps.
    IUniswapV2Router02 public _uniswapRouter;

    // Withdrawal admins
    mapping(address => bool) public allowedAddresses;
    uint256 public withdrawalEnabledTimestamp;


    constructor(address _dai, address _paxg, address _wbtc, address _dnm) {
        DAI = _dai;
        PAXG = _paxg;
        WBTC = _wbtc;
        DNM = _dnm;

        ALLOCATION_PAXG = 30; 
        ALLOCATION_WBTC = 30; 
        ALLOCATION_DAI = 40;

        WITHDRAWAL_DELAY = 90 days;

        _slippageBps = 100;
        _slippageDenominator = 10000;
    }
}