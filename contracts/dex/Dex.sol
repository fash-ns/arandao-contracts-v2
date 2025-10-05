// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {DexStorage} from "./DexCore/DexStorage.sol";
import {DexHelper} from "./DexCore/DexHelper.sol";
import {DexErrors} from "./DexCore/DexErrors.sol";

/**
 * @title Dex
 * @notice The main contract for the ERC20 Order Book, providing public trading interfaces.
 * @dev Implements the core logic by leveraging inherited storage and helper functionalities.
 */
contract Dex is Ownable, ReentrancyGuard, DexStorage, DexHelper {
  /**
   * @notice Initializes the contract with tokens, fee recipient, and fee tiers.
   * @param initialOwner The address of the contract owner.
   * @param _dnmToken The address of the base token (e.g., DNM).
   * @param _daiToken The address of the quote token (e.g., DAI).
   * @param _feeReceiver The address designated to receive trading fees.
   * @param _vault The address of the vault for getting dnm price range
   * @param _feeTiers The configuration array for tiered fee structure.
   */
  constructor(
    address initialOwner,
    address _dnmToken,
    address _daiToken,
    address _feeReceiver,
    address _vault,
    FeeTier[] memory _feeTiers
  )
    Ownable(initialOwner)
    DexStorage(_dnmToken, _daiToken, _feeReceiver, _vault, _feeTiers)
  {}

  /**
   * @notice Places a new buy order (Maker is selling DAI, buying DNM).
   * @dev Requires the maker to have approved the contract to spend the DAI equivalent of (amount * price).
   * @param amount The amount of DNM (base token) to buy.
   * @param price The price of DNM in DAI (quote token) per DNM (scaled by 1e18).
   */
  function placeBuyOrder(
    uint256 amount,
    uint256 price
  ) external onlyValidPrice(price) nonReentrant {
    if (amount == 0 || price == 0) revert DexErrors.InvalidAmounts();

    // Maker must transfer DAI to contract as collateral for the trade
    uint256 daiCollateral = (amount * price) / (10 ** 18);
    _handleTransferFrom(daiToken, msg.sender, address(this), daiCollateral);

    _createOrder(msg.sender, amount, price, false); // false for Buy Order
  }

  /**
   * @notice Places a new sell order (Maker is selling DNM, buying DAI).
   * @dev Requires the maker to have approved the contract to spend the DNM `amount`.
   * @param amount The amount of DNM (base token) to sell.
   * @param price The price of DNM in DAI (quote token) per DNM (scaled by 1e18).
   */
  function placeSellOrder(
    uint256 amount,
    uint256 price
  ) external onlyValidPrice(price) nonReentrant {
    if (amount == 0 || price == 0) revert DexErrors.InvalidAmounts();

    // Maker must transfer DNM to contract as collateral for the trade
    _handleTransferFrom(dnmToken, msg.sender, address(this), amount);

    _createOrder(msg.sender, amount, price, true); // true for Sell Order
  }

  /**
   * @notice Cancels an existing active order. Only the maker can call this.
   * @dev The calling contract should handle the refund of collateral.
   * @param orderId The ID of the order to cancel.
   */
  function cancelOrder(
    uint256 orderId
  ) external onlyActiveOrder(orderId) nonReentrant {
    // Validation: Only the maker can cancel their own order
    if (orders[orderId].maker != msg.sender) {
      revert DexErrors.Unauthorized();
    }

    // The helper handles the status update and event emission
    _cancelOrder(msg.sender, orderId);

    // Refund the maker their collateral based on order type
    _refundMaker(orderId);
  }

  /**
   * @notice Executes a full trade against an existing active order (Taker).
   * @param orderId The ID of the order to execute.
   */
  function executeOrder(
    uint256 orderId
  ) external onlyActiveOrder(orderId) nonReentrant {
    // The `_executeTrade` function handles all token transfers (collateral from contract, funds from taker, fees).
    _executeOrder(orderId, msg.sender);
  }

  /**
   * @notice Retrieves the details of a specific order.
   * @param orderId The ID of the order to retrieve.
   * @return Order struct containing all order details.
   */
  function getOrder(uint256 orderId) external view returns (Order memory) {
    // Simple getter function. Does not require a helper.
    if (orderId == 0 || orderId >= nextOrderId) {
      revert DexErrors.OrderNotFound();
    }
    return orders[orderId];
  }

  /**
   * @notice Retrieves all order IDs associated with a specific user.
   * @param user The address of the user.
   * @return An array of Order structs associated with the user.
   */
  function getUserOrders(address user) external view returns (Order[] memory) {
    uint256[] storage userOrderIds = makerOrders[user];
    Order[] memory userOrders = new Order[](userOrderIds.length);

    for (uint256 i = 0; i < userOrderIds.length; i++) {
      userOrders[i] = orders[userOrderIds[i]];
    }
    return userOrders;
  }
}
