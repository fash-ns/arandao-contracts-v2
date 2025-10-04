// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import {IUniswapV2Router02} from "@uniswap/v2-periphery/contracts/interfaces/IUniswapV2Router02.sol";
import {IPriceFeed} from "../interfaces/IPriceFeed.sol";

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
  address public immutable DNM;

  // Asset Allocation Percentages (out of 100)
  uint256 public immutable ALLOCATION_PAXG = 30;
  uint256 public immutable ALLOCATION_WBTC = 30;
  uint256 public immutable ALLOCATION_DAI = 40;

  /// @dev Duration for the emergency withdrawal grace period.
  uint256 public immutable WITHDRAWAL_DELAY = 120 days;

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
  IUniswapV2Router02 internal _uniswapRouter;
  IPriceFeed internal _priceFeed;

  // Withdrawal admins and core contract
  address public coreContract;
  mapping(address => bool) public isAdmin;

  /// @notice The timestamp after which the emergencyWithdrawal function can be called.
  uint256 public withdrawalEnabledTimestamp;

  /**
   * @notice Initializes all immutable token addresses, the price feed, sets the admin grace period,
   * and designates up to three initial administrators.
   * @param _admin1 The address of the first initial administrator.
   * @param _admin2 The address of the second initial administrator.
   * @param _admin3 The address of the third initial administrator.
   */
  constructor(
    address _dai,
    address _paxg,
    address _wbtc,
    address _dnm,
    address _feedAddr,
    address _coreAddr,
    address _routerAddr,
    address _admin1,
    address _admin2,
    address _admin3,
    address _feeReceiver
  ) {
    DAI = _dai;
    PAXG = _paxg;
    WBTC = _wbtc;
    DNM = _dnm;

    _priceFeed = IPriceFeed(_feedAddr);
    coreContract = _coreAddr;
    _uniswapRouter = IUniswapV2Router02(_routerAddr);

    FEE_RECEIVER = _feeReceiver;

    // Set initial administrators, ignoring the zero address
    if (_admin1 != address(0)) {
      isAdmin[_admin1] = true;
    }
    if (_admin2 != address(0)) {
      isAdmin[_admin2] = true;
    }
    if (_admin3 != address(0)) {
      isAdmin[_admin3] = true;
    }

    // Set the timestamp when emergency withdrawal becomes available
    withdrawalEnabledTimestamp = block.timestamp + WITHDRAWAL_DELAY;
  }
}
