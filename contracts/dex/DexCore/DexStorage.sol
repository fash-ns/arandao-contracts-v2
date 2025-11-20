// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {DexErrors} from "./DexErrors.sol";
import {IMultiAssetVault} from "../interfaces/IMultiAssetVault.sol";
import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";

/**
 * @title DexStorage
 * @dev This abstract contract defines the persistent state and data structures for the OrderBook.
 */
abstract contract DexStorage is Initializable {
  /**
   * @dev Defines the lifecycle status of an order.
   */
  enum Status {
    NotActive, // Initial state / deleted placeholder
    Active, // Order is live and partially or fully fillable
    Canceled, // Order was canceled by the maker
    Executed // Order was fully filled
  }

  /**
   * @dev Defines a fee tier boundary and its corresponding fee rate.
   * @param volumeFloor The minimum trade volume **in DAI** (quote token) required to qualify for this tier.
   * 10**18).
   * @param makerFeeBps The fee rate for makers in basis points (1 BPS = 0.01%).
   * @param takerFeeBps The fee rate for takers in basis points (1 BPS = 0.01%).
   */
  struct FeeTier {
    uint256 volumeFloor; // Minimum trade value in DAI (quote token) to qualify for this fee tier (this should be passed in scaled by 1e18)
    uint16 makerFeeBps; // Fee in basis points (max 9999)
    uint16 takerFeeBps; // Fee in basis points (max 9999)
  }

  /**
   * @dev Represents a limit order placed in the book.
   * @param id Unique identifier.
   * @param maker The address that placed the order.
   * @param isSell True for Sell DNM, False for Buy DNM.
   * @param amount full amount of DNM to trade.
   * @param price Price: DAI per 1 DNM (multiplied by 1e18 for precision).
   * @param status Current status in the order lifecycle.
   */
  struct Order {
    uint256 id;
    address maker;
    bool isSell;
    uint256 amount;
    uint256 price;
    Status status;
  }

  // --- State Variables ---

  /// @notice The ERC20 token being traded (e.g., DNM).
  address public dnmToken;
  /// @notice The ERC20 token used for payment (e.g., DAI).
  address public daiToken;

  /// @notice Deadline timestamp after which upgrades are disabled.
  uint256 public upgradeDeadline;

  /// @notice Indicates if the fee receiver address has been changed.
  bool public isFeeReceiverChanged;

  /// @notice Flag indicating if ownership has been transferred.
  bool public ownershipFlag;

  /// @notice The address that receives the trading fees.
  address public feeReceiver;

  /// @notice The vault contract for secure token transfers.
  IMultiAssetVault internal vault;

  /// @notice Ordered list of fee tiers. Must be sorted by volumeFloor in ascending order.
  FeeTier[] public feeTiers;

  /// @notice Unique identifier for the next new order.
  uint256 public nextOrderId;

  /// @notice Mapping from order ID to the order details.
  mapping(uint256 => Order) public orders;

  /// @notice Mapping for quick lookup of order IDs by maker.
  mapping(address => uint256[]) public makerOrders;

  /**
   * @dev Initializes the immutable token addresses and fee configuration.
   * @param _dnmToken Address of the DNM ERC20 token.
   * @param _daiToken Address of the DAI ERC20 token.
   * @param _feeReceiver Address to send the collected fees.
   */
  function __DexStorage_init(
    address _dnmToken,
    address _daiToken,
    address _feeReceiver,
    address _vault
  ) internal onlyInitializing {
    if (
      _dnmToken == address(0) ||
      _daiToken == address(0) ||
      _feeReceiver == address(0) ||
      _vault == address(0)
    ) {
      revert DexErrors.ZeroAddress();
    }
    if (_dnmToken == _daiToken) {
      revert DexErrors.SameTokens();
    }

    // --- Initialize Immutable State Variables ---
    dnmToken = _dnmToken;
    daiToken = _daiToken;
    feeReceiver = _feeReceiver;
    vault = IMultiAssetVault(_vault);
    nextOrderId = 1;
    upgradeDeadline = block.timestamp + 90 days;

    // --- Initialize Fee Tiers ---
    // Fee tiers based on trading volume (USD equivalent)
    // Below $1,000
    feeTiers.push(
      FeeTier({
        volumeFloor: 0,
        makerFeeBps: 80, // 0.80%
        takerFeeBps: 100 // 1.00%
      })
    );

    // $1,000 - $5,000
    feeTiers.push(
      FeeTier({
        volumeFloor: 1_000 ether,
        makerFeeBps: 72, // 0.72%
        takerFeeBps: 90 // 0.90%
      })
    );

    // $5,000 - $40,000
    feeTiers.push(
      FeeTier({
        volumeFloor: 5_000 ether,
        makerFeeBps: 64, // 0.64%
        takerFeeBps: 72 // 0.72%
      })
    );

    // $40,000 - $100,000
    feeTiers.push(
      FeeTier({
        volumeFloor: 40_000 ether,
        makerFeeBps: 50, // 0.50%
        takerFeeBps: 68 // 0.68%
      })
    );

    // $100,000 - $1,000,000
    feeTiers.push(
      FeeTier({
        volumeFloor: 100_000 ether,
        makerFeeBps: 40, // 0.40%
        takerFeeBps: 54 // 0.54%
      })
    );

    // Above $1,000,000
    feeTiers.push(
      FeeTier({
        volumeFloor: 1_000_000 ether,
        makerFeeBps: 30, // 0.30%
        takerFeeBps: 48 // 0.48%
      })
    );
  }
}
