// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import {ISwapRouter} from "@uniswap/v3-periphery/contracts/interfaces/ISwapRouter.sol";
import {IPriceFeed} from "../interfaces/IPriceFeed.sol";
import {IQuoter} from "@uniswap/v3-periphery/contracts/interfaces/IQuoter.sol";
import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";

/**
 * @title VaultStorage
 * @notice Abstract contract defining all immutable token addresses, allocations,
 * administrative variables, and external interfaces for the vault.
 */
abstract contract VaultStorage is Initializable {
  // Token Addresses
  address public DAI;
  address public PAXG;
  address public WBTC;
  address public USDC;
  address public ARC;

  // Asset Allocation Percentages (out of 100)
  uint256 public constant ALLOCATION_PAXG = 30;
  uint256 public constant ALLOCATION_WBTC = 30;
  uint256 public constant ALLOCATION_DAI = 40;

  // Duration for the emergency withdrawal grace period
  uint256 public constant WITHDRAWAL_DELAY = 90 days;

  /**
   * @dev Defines a fee tier boundary and its corresponding fee rate.
   * @param volumeFloor The minimum initial DNM amount (scaled by 1e18) to qualify for this tier.
   * @param feeBps The fee percentage (in basis points, e.g., 5 for 0.05%) for this tier.
   */
  struct FeeTier {
    uint256 volumeFloor; // Minimum DAI amount (scaled 1e18)
    uint16 feeBps; // Fee in basis points (max 9999)
  }

  // Fee Tiers Configuration
  FeeTier[] public feeTiers;

  /// @dev Flag to ensure ownership is transferred only once.
  bool public ownershipFlag;

  /// @dev The timestamp after which upgrades are no longer allowed.
  uint256 public upgradeDeadline;

  bool public feeReceiverFlag;
  address public feeReceiver;

  uint256 public constant BPS_DENOMINATOR = 10000;

  /// @dev The maximum accepted slippage for swaps E.g., 100 = 1%.
  uint256 internal _slippageBps;
  /// @dev The denominator used for slippage calculation (10000 for BPS).
  uint256 internal _slippageDenominator;
  /// @dev The duration (in seconds) added to block.timestamp to set the swap transaction deadline.
  uint256 internal _deadlineDuration;

  // External Interfaces (stored as addresses/typed interfaces)
  ISwapRouter internal _uniswapRouter;
  IQuoter internal _uniswapQuoter;
  IPriceFeed internal _priceFeed;

  // Uniswap V3 fees
  uint24 internal _feeDefault;
  uint24 internal _feeUsdcDai;
  uint24 internal _feeUsdcWbtc;
  uint24 internal _feeUsdcPaxg;

  // Withdrawal admins and core contract
  address public coreContract;

  /// @notice The timestamp after which the emergencyWithdrawal function can be called.
  uint256 public withdrawalEnabledTimestamp;

  // Emergency swap control
  bool public isSwapEnabled;

  /// @notice Struct for initialization parameters
  struct InitParams {
    address dai;
    address paxg;
    address wbtc;
    address usdc;
    address arc;
    address priceFeed;
    address coreContract;
    address uniswapRouter;
    address uniswapQuoter;
    address initialOwner;
    address feeReceiver;
  }

  /**
   * @dev Initialize storage values. This function is internal and intended to be
   * called by the implementation contract's initializer (which should have the
   * `initializer` modifier from OpenZeppelin).
   */
  function __VaultStorage_init(
    InitParams memory params
  ) internal onlyInitializing {
    DAI = params.dai;
    PAXG = params.paxg;
    WBTC = params.wbtc;
    USDC = params.usdc;
    ARC = params.arc;

    _priceFeed = IPriceFeed(params.priceFeed);
    coreContract = params.coreContract;
    _uniswapRouter = ISwapRouter(params.uniswapRouter);
    _uniswapQuoter = IQuoter(params.uniswapQuoter);

    feeReceiver = params.feeReceiver;

    /// @dev Set the upgrade deadline to 90 days from initialization
    upgradeDeadline = block.timestamp + 90 days;

    // Set the timestamp when emergency withdrawal becomes available
    withdrawalEnabledTimestamp = block.timestamp + WITHDRAWAL_DELAY;

    // Default Uniswap fees
    _feeDefault = 3000;
    _feeUsdcDai = 100;
    _feeUsdcWbtc = 500;
    _feeUsdcPaxg = 3000;

    ownershipFlag = false;
    feeReceiverFlag = false;

    // Under $1,000
    feeTiers.push(
      FeeTier({
        volumeFloor: 0,
        feeBps: 80 // 0.8%
      })
    );

    // $1,000 - $5,000
    feeTiers.push(
      FeeTier({
        volumeFloor: 1_000 ether,
        feeBps: 72 // 0.72%
      })
    );

    // $5,000 - $40,000
    feeTiers.push(
      FeeTier({
        volumeFloor: 5_000 ether,
        feeBps: 64 // 0.64%
      })
    );

    // $40,000 - $100,000
    feeTiers.push(
      FeeTier({
        volumeFloor: 40_000 ether,
        feeBps: 50 // 0.5%
      })
    );

    // $100,000 - $1,000,000
    feeTiers.push(
      FeeTier({
        volumeFloor: 100_000 ether,
        feeBps: 40 // 0.4%
      })
    );

    // Above $1,000,000
    feeTiers.push(
      FeeTier({
        volumeFloor: 1_000_000 ether,
        feeBps: 30 // 0.3%
      })
    );
  }
}
