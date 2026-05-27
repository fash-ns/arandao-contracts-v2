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
 * @dev Supports both full and partial fills. It inherits required storage fields from DexStorage.
 */
abstract contract DexHelper is DexStorage {
    using SafeERC20 for IERC20;

    event OrderPlaced(uint256 orderId, address maker, bool isSell, uint256 amountArc, uint256 price);
    event OrderCanceled(uint256 orderId, address maker);
    event OrderFilled(
        uint256 orderId,
        address maker,
        address taker,
        uint256 filledAmount,
        uint256 arcTraded,
        uint256 usdtTraded,
        uint256 arcFee,
        uint256 usdtFee
    );

    modifier onlyActiveOrder(uint256 orderId) {
        _onlyActiveOrder(orderId);
        _;
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
     */
    function _handleTransferFrom(address token, address from, address to, uint256 amount) internal {
        IERC20(token).safeTransferFrom(from, to, amount);
    }

    /**
     * @notice Safely transfers tokens from the contract to a recipient.
     */
    function _handleTransfer(address token, address to, uint256 amount) internal {
        IERC20(token).safeTransfer(to, amount);
    }

    /**
     * @notice Creates a new active order and increments the global order ID counter.
     * @param lockedUsdt Exact USDT collateral held by the contract; 0 for sell orders.
     */
    function _createOrder(address user, uint256 amount, uint256 price, bool isSell, uint256 lockedUsdt) internal {
        uint256 orderId = nextOrderId++;

        orders[orderId] = Order({
            id: orderId,
            maker: user,
            isSell: isSell,
            amount: amount,
            price: price,
            lockedUsdt: lockedUsdt,
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
     * @notice Executes a trade (partial or full) against an active order, handling transfers and fees.
     * @param orderId The ID of the order to execute.
     * @param taker The taker address executing the fill.
     * @param amount The amount of ARC being filled from the order (<= order.amount).
     */
    function _executeOrder(uint256 orderId, address taker, uint256 amount) internal {
        Order storage order = orders[orderId];

        if (amount == 0) revert DexErrors.InvalidAmounts();
        if (order.amount < amount) revert DexErrors.InsufficientOrderAmount();
        if (order.maker == taker) revert DexErrors.CannotFillOwnOrder();

        uint256 arcTraded = amount;
        uint256 usdtTraded = (arcTraded * order.price) / (10 ** 18);
        if (usdtTraded == 0) revert DexErrors.InvalidAmounts();

        (uint16 applicableMakerFeeBps, uint16 applicableTakerFeeBps) = _getFeeRate(usdtTraded);

        uint256 arcFee = (arcTraded * applicableTakerFeeBps) / 10000;
        uint256 usdtFee = (usdtTraded * applicableMakerFeeBps) / 10000;

        address maker = order.maker;
        bool isSell = order.isSell;

        // CEI: write all state before any external call
        order.amount -= amount;
        uint256 dustUsdt = 0;
        if (!isSell) {
            // floor-sum inequality guarantees lockedUsdt never underflows across partial fills
            order.lockedUsdt -= usdtTraded;
            // On the final fill, sweep any rounding dust so it is never permanently locked
            if (order.amount == 0 && order.lockedUsdt > 0) {
                dustUsdt = order.lockedUsdt;
                order.lockedUsdt = 0;
            }
        }
        if (order.amount == 0) order.status = Status.Executed;

        if (isSell) {
            // Maker placed a SELL ARC order (locked ARC). Taker sends USDT to buy ARC.
            _handleTransferFrom(usdtToken, taker, address(this), usdtTraded);
            _handleTransfer(usdtToken, maker, usdtTraded - usdtFee);
            _handleTransfer(usdtToken, feeReceiver, usdtFee);
            _handleTransfer(arcToken, taker, arcTraded - arcFee);
            _handleTransfer(arcToken, feeReceiver, arcFee);
        } else {
            // Maker placed a BUY ARC order (locked USDT). Taker sends ARC to sell.
            _handleTransferFrom(arcToken, taker, address(this), arcTraded);
            _handleTransfer(arcToken, maker, arcTraded - arcFee);
            _handleTransfer(arcToken, feeReceiver, arcFee);
            _handleTransfer(usdtToken, taker, usdtTraded - usdtFee);
            _handleTransfer(usdtToken, feeReceiver, usdtFee + dustUsdt);
        }

        emit OrderFilled(orderId, maker, taker, amount, arcTraded, usdtTraded, arcFee, usdtFee);
    }

    /**
     * @notice Refunds the maker of a canceled order their collateral.
     * @dev Uses the exact tracked amounts to avoid integer-division dust discrepancies.
     */
    function _refundMaker(uint256 orderId, address account) internal {
        Order storage order = orders[orderId];
        if (order.isSell) {
            _handleTransfer(arcToken, account, order.amount);
        } else {
            // Return exactly what was locked, not a recomputed approximation
            _handleTransfer(usdtToken, account, order.lockedUsdt);
        }
    }

    /**
     * @notice Determines the applicable fee rate based on the USDT volume.
     * @dev Assumes the `feeTiers` array is correctly sorted by `volumeFloor` in ascending order.
     */
    function _getFeeRate(uint256 usdtAmount)
        internal
        view
        returns (uint16 applicableMakerFeeBps, uint16 applicableTakerFeeBps)
    {
        applicableMakerFeeBps = feeTiers[0].makerFeeBps;
        applicableTakerFeeBps = feeTiers[0].takerFeeBps;

        for (uint256 i = 0; i < feeTiers.length; i++) {
            if (usdtAmount >= feeTiers[i].volumeFloor) {
                applicableMakerFeeBps = feeTiers[i].makerFeeBps;
                applicableTakerFeeBps = feeTiers[i].takerFeeBps;
            } else {
                // Optimization: break since array is sorted
                break;
            }
        }
    }
}
