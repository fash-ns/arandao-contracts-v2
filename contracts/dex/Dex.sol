// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {DexStorage} from "./DexCore/DexStorage.sol";
import {DexHelper} from "./DexCore/DexHelper.sol";
import {DexErrors} from "./DexCore/DexErrors.sol";

/**
 * @title Dex
 * @notice The main contract for the ERC20 Order Book, providing public trading interfaces.
 * @dev Implements the core logic by leveraging inherited storage and helper functionalities.
 */
contract Dex is ReentrancyGuard, DexStorage, DexHelper {
    /**
     * @notice Deploys the Dex contract with necessary parameters.
     * @param _arcToken The address of the base token (ARC).
     * @param _usdtToken The address of the quote token (USDT).
     * @param _feeReceiver The address designated to receive trading fees.
     */
    constructor(address _arcToken, address _usdtToken, address _feeReceiver) {
        __DexStorage_init(_arcToken, _usdtToken, _feeReceiver);
    }

    /**
     * @notice Places a new buy order (Maker is selling USDT, buying ARC).
     * @dev Requires the maker to have approved the contract to spend the USDT equivalent of (amount * price).
     * @param amount The amount of ARC (base token) to buy.
     * @param price The price of ARC in USDT (quote token) per ARC (scaled by 1e18).
     */
    function placeBuyOrder(uint256 amount, uint256 price) external nonReentrant {
        if (amount == 0) revert DexErrors.InvalidAmounts();

        // Maker must transfer USDT to contract as collateral for the trade
        uint256 usdtCollateral = (amount * price) / (10 ** 18);
        _handleTransferFrom(usdtToken, msg.sender, address(this), usdtCollateral);

        _createOrder(msg.sender, amount, price, false); // false for Buy Order
    }

    /**
     * @notice Places a new sell order (Maker is selling ARC, buying USDT).
     * @dev Requires the maker to have approved the contract to spend the ARC `amount`.
     * @param amount The amount of ARC (base token) to sell.
     * @param price The price of ARC in USDT (quote token) per ARC (scaled by 1e18).
     */
    function placeSellOrder(uint256 amount, uint256 price) external nonReentrant {
        if (amount == 0) revert DexErrors.InvalidAmounts();

        // Maker must transfer ARC to contract as collateral for the trade
        _handleTransferFrom(arcToken, msg.sender, address(this), amount);

        _createOrder(msg.sender, amount, price, true); // true for Sell Order
    }

    /**
     * @notice Cancels an existing active order. Only the maker can call this.
     * @dev The calling contract should handle the refund of collateral.
     * @param orderId The ID of the order to cancel.
     */
    function cancelOrder(uint256 orderId) external onlyActiveOrder(orderId) nonReentrant {
        address caller = msg.sender;

        // Validation: Only the maker can cancel their own order
        if (orders[orderId].maker != caller) {
            revert DexErrors.Unauthorized();
        }

        // The helper handles the status update and event emission
        _cancelOrder(caller, orderId);

        // Refund the maker their collateral based on order type
        _refundMaker(orderId, caller);
    }

    /**
     * @notice Executes a full trade against an existing active order (Taker).
     * @param orderId The ID of the order to execute.
     */
    function executeOrder(uint256 orderId, uint256 amount) external onlyActiveOrder(orderId) nonReentrant {
        // The `_executeTrade` function handles all token transfers (collateral from contract, funds from taker, fees).
        _executeOrder(orderId, msg.sender, amount);
    }

    /**
     * @notice Retrieves the details of a specific order.
     * @param orderId The ID of the order to retrieve.
     * @return Order struct containing all order details.
     */
    function getOrder(uint256 orderId) external view returns (Order memory) {
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
