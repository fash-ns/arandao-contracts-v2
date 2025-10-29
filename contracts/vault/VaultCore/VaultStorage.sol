// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {ISwapRouter} from "@uniswap/v3-periphery/contracts/interfaces/ISwapRouter.sol";
import {IPriceFeed} from "../interfaces/IPriceFeed.sol";
import {IQuoterV2} from "@uniswap/v3-periphery/contracts/interfaces/IQuoterV2.sol";

/**
 * @title VaultStorage
 * @notice Abstract contract defining all immutable token addresses, allocations,
 * administrative variables, and external interfaces for the vault.
 */
abstract contract VaultStorage {
  // Token Addresses (immutable for gas efficiency and security)
  address public immutable DAI;
  address public immutable PAXG;
  address public immutable WBTC;
  address public immutable USDC;
  address public immutable DNM;

  // Asset Allocation Percentages (out of 100)
  uint256 public immutable ALLOCATION_PAXG = 30;
  uint256 public immutable ALLOCATION_WBTC = 30;
  uint256 public immutable ALLOCATION_DAI = 40;

  /// @dev Duration for the emergency withdrawal grace period.
  uint256 public immutable WITHDRAWAL_DELAY = 90 days;

  uint256 public immutable REDEEM_FEE_BPS = 300;
  uint256 public immutable BPS_DENOMINATOR = 10000;
  address public immutable FEE_RECEIVER;

  // --- ADDED SWAP CONFIGURATION VARIABLES BACK FOR INHERITANCE ---
  /// @dev The maximum accepted slippage for swaps E.g., 100 = 1%.
  uint256 internal _slippageBps = 100;
  /// @dev The denominator used for slippage calculation (10000 for BPS).
  uint256 internal _slippageDenominator = 10000;
  /// @dev The duration (in seconds) added to block.timestamp to set the swap transaction deadline.
  uint256 internal _deadlineDuration = 10 minutes;

  // External Interfaces
  ISwapRouter internal _uniswapRouter;
  IQuoterV2 internal _uniswapQuoter;
  IPriceFeed internal _priceFeed;

  // Uniswap V3 fees
  uint24 internal _feeDefault = 3000;
  uint24 internal _feeUsdcDai = 100;
  uint24 internal _feeUsdcWbtc = 500;
  uint24 internal _feeUsdcPaxg = 3000;

  // Withdrawal admins and core contract
  address public coreContract;
  mapping(address => bool) public isAdmin;

  /// @notice The timestamp after which the emergencyWithdrawal function can be called.
  uint256 public withdrawalEnabledTimestamp;

  /// @notice Struct for initialization parameters
  struct InitParams {
    address dai;
    address paxg;
    address wbtc;
    address usdc;
    address dnm;
    address priceFeed;
    address uniswapRouter;
    address uniswapQuoter;
    address admin1;
    address admin2;
    address admin3;
    address feeReceiver;
  }

  /**
   * @notice Initializes all immutable token addresses, the price feed, sets the admin grace period,
   * and designates up to three initial administrators.
   * @param params Struct containing all initialization parameters.
   */
  constructor(InitParams memory params) {
    DAI = params.dai;
    PAXG = params.paxg;
    WBTC = params.wbtc;
    USDC = params.usdc;
    DNM = params.dnm;

    _priceFeed = IPriceFeed(params.priceFeed);
    _uniswapRouter = ISwapRouter(params.uniswapRouter);
    _uniswapQuoter = IQuoterV2(params.uniswapQuoter);

    FEE_RECEIVER = params.feeReceiver;

    // Set initial administrators, ignoring the zero address
    if (params.admin1 != address(0)) isAdmin[params.admin1] = true;
    if (params.admin2 != address(0)) isAdmin[params.admin2] = true;
    if (params.admin3 != address(0)) isAdmin[params.admin3] = true;

    // Set the timestamp when emergency withdrawal becomes available
    withdrawalEnabledTimestamp = block.timestamp + WITHDRAWAL_DELAY;
  }
}
