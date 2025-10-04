// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {DexStorage} from "./DexStorage.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {DexErrors} from "./DexErrors.sol";

/**
 * @title DexHelper
 * @notice Provides internal helper functions for core DEX operations, including token handling,
 * order creation, cancellation, execution, and fee calculation.
 * @dev This abstract contract assumes a full-fill execution model, meaning any accepted order
 * is completed in its entirety. It inherits required storage fields from DexStorage.
 */
abstract contract DexHelper is DexStorage {
  using SafeERC20 for IERC20;

  event OrderPlaced(
    uint256 orderId,
    address maker,
    bool isSell,
    uint256 amountDNM,
    uint256 price
  );
  event OrderCanceled(uint256 orderId, address maker);
  event OrderFilled(
    uint256 orderId,
    address maker,
    address taker,
    uint256 dnmTraded,
    uint256 daiTraded,
    uint256 dnmFee,
    uint256 daiFee
  );
  event FeesWithdrawn(address feeReceiver, address token, uint256 amount);

  modifier onlyActiveOrder(uint256 orderId) {
    _onlyActiveOrder(orderId);
    _;
  }

  modifier onlyValidPrice(uint256 price) {
    _onlyValidPrice(price);
    _;
  }

  /**
   * @notice Validates that the provided price is within the acceptable range.
   * @dev This example assumes a simplistic check against a vault price. Adjust logic as needed.
   */
  function _onlyValidPrice(uint256 price) internal view {
    uint256 vaultPrice = vault.getPrice();
    if (price < vaultPrice) revert DexErrors.PriceOutOfRange();
  }

  /**
   * @notice Validates that the specified order is active.
   * @dev Reverts if the order is not in Active status.
   */
  function _onlyActiveOrder(uint256 orderId) internal view {
    if (orders[orderId].status != Status.Active) {
      revert DexErrors.OrderNotActive();
    }
  }

  /**
   * @notice Safely transfers tokens from a specified address to another.
   * @dev Prevents execution if the amount is zero.
   */
  function _handleTransferFrom(
    address token,
    address from,
    address to,
    uint256 amount
  ) internal {
    IERC20(token).safeTransferFrom(from, to, amount);
  }

  /**
   * @notice Safely transfers tokens from the contract to a recipient.
   * @dev Prevents execution if the amount is zero.
   */
  function _handleTransfer(address token, address to, uint256 amount) internal {
    IERC20(token).safeTransfer(to, amount);
  }

  /**
   * @notice Creates a new active order and increments the global order ID counter.
   */
  function _createOrder(
    address user,
    uint256 amount,
    uint256 price,
    bool isSell
  ) internal {
    uint256 orderId = nextOrderId++;

    orders[orderId] = Order({
      id: orderId,
      maker: user,
      taker: address(0),
      isSell: isSell,
      amount: amount,
      price: price,
      status: Status.Active
    });

    makerOrders[user].push(orderId);
    emit OrderPlaced(orderId, user, isSell, amount, price);
  }

  /**
   * @notice Sets the status of an existing order to Canceled.
   * @dev The calling contract is responsible for any necessary refund logic.
   */
  function _cancelOrder(address user, uint256 orderId) internal {
    orders[orderId].status = Status.Canceled;
    emit OrderCanceled(orderId, user);
  }

  /**
   * @notice Executes a full trade against an active order, handling all token transfers and fees.
   * @dev Assumes full fulfillment. Updates order status to Executed and amount to 0.
   */
  function _executeOrder(uint256 orderId, address taker) internal {
    Order storage order = orders[orderId];

    _onlyValidPrice(order.price);
    if (orders[orderId].maker == msg.sender)
      revert DexErrors.CannotFillOwnOrder();

    // Update order state
    order.status = Status.Executed;
    order.taker = taker;

    uint256 dnmTraded = order.amount;
    uint256 daiTraded = (dnmTraded * order.price) / (10 ** 18);

    uint16 feeBps = _getFeeRate(dnmTraded);

    uint256 dnmFee = (dnmTraded * feeBps) / 10000;
    uint256 daiFee = (daiTraded * feeBps) / 10000;

    address maker = order.maker;

    if (order.isSell) {
      // Maker is selling DNM, Taker is buying DNM (paying DAI).

      // 1. Taker transfers DAI to the contract
      _handleTransferFrom(daiToken, taker, address(this), daiTraded);

      // 2. Distribute net DAI to Maker and DAI fees to feeReceiver
      _handleTransfer(daiToken, maker, daiTraded - daiFee);
      _handleTransfer(daiToken, feeReceiver, daiFee);

      // 3. Distribute net DNM to Taker and DNM fees to feeReceiver
      _handleTransfer(dnmToken, taker, dnmTraded - dnmFee);
      _handleTransfer(dnmToken, feeReceiver, dnmFee);
    } else {
      // Maker is buying DNM, Taker is selling DNM (receiving DAI).

      // 1. Taker transfers DNM to the contract
      _handleTransferFrom(dnmToken, taker, address(this), dnmTraded);

      // 2. Distribute net DNM to Maker and DNM fees to feeReceiver
      _handleTransfer(dnmToken, maker, dnmTraded - dnmFee);
      _handleTransfer(dnmToken, feeReceiver, dnmFee);

      // 3. Distribute net DAI to Taker and DAI fees to feeReceiver
      _handleTransfer(daiToken, taker, daiTraded - daiFee);
      _handleTransfer(daiToken, feeReceiver, daiFee);
    }

    emit OrderFilled(
      orderId,
      maker,
      taker,
      dnmTraded,
      daiTraded,
      dnmFee,
      daiFee
    );
  }

  /**
   * @notice Refunds the maker of a canceled order their collateral.
   * @dev The calling contract should ensure this is only called for canceled orders.
   */
  function _refundMaker(uint256 orderId) internal {
    Order storage order = orders[orderId];
    uint256 refundAmount = order.amount;

    if (order.isSell) {
      _handleTransfer(dnmToken, msg.sender, refundAmount);
    } else {
      // Refund DAI collateral
      uint256 daiToRefund = (refundAmount * order.price) / (10 ** 18);
      _handleTransfer(daiToken, msg.sender, daiToRefund);
    }
  }

  /**
   * @notice Determines the applicable fee rate based on the DNM trade volume.
   * @dev Assumes the `feeTiers` array is correctly sorted by `volumeFloor` in ascending order.
   */
  function _getFeeRate(
    uint256 dnmAmount
  ) internal view returns (uint16 feeBps) {
    uint16 applicableFeeBps = feeTiers[0].feeBps;

    for (uint256 i = 0; i < feeTiers.length; i++) {
      if (dnmAmount >= feeTiers[i].volumeFloor) {
        applicableFeeBps = feeTiers[i].feeBps;
      } else {
        // Optimization: break since array is sorted
        break;
      }
    }
    return applicableFeeBps;
  }
}
