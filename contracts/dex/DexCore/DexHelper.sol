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
        if (price < vaultPrice || price == 0) revert DexErrors.PriceOutOfRange();
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
    function _handleTransferFrom(address token, address from, address to, uint256 amount) internal {
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
    function _createOrder(address user, uint256 amount, uint256 price, bool isSell) internal {
        uint256 orderId = nextOrderId++;

        orders[orderId] =
            Order({id: orderId, maker: user, isSell: isSell, amount: amount, price: price, status: Status.Active});

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

        _onlyValidPrice(order.price);

        if (amount == 0) revert DexErrors.InvalidAmounts();
        if (order.amount < amount) revert DexErrors.InsufficientOrderAmount();
        if (order.maker == taker) revert DexErrors.CannotFillOwnOrder();

        // Calculate traded amounts for this partial fill
        uint256 arcTraded = amount;
        uint256 usdtTraded = (arcTraded * order.price) / (10 ** 18);

        // Determine applicable fees based on USDT volume
        (uint16 applicableMakerFeeBps, uint16 applicableTakerFeeBps) = _getFeeRate(usdtTraded);

        // Calculate fees
        uint256 arcFee = (arcTraded * applicableTakerFeeBps) / 10000; // taker pays ARC fee when selling ARC
        uint256 usdtFee = (usdtTraded * applicableMakerFeeBps) / 10000; // maker pays USDT fee when receiving USDT

        address maker = order.maker;

        if (order.isSell) {
            // Maker placed a SELL ARC order (maker had locked ARC in contract).
            // Taker buys ARC by sending USDT.

            // 1. Taker transfers appropriate USDT for this partial fill
            _handleTransferFrom(usdtToken, taker, address(this), usdtTraded);

            // 2. Pay maker (USDT) net of maker fee, and send fee to feeReceiver
            _handleTransfer(usdtToken, maker, usdtTraded - usdtFee);
            _handleTransfer(usdtToken, feeReceiver, usdtFee);

            // 3. Transfer ARC net of taker fee to taker, and ARC fee to feeReceiver
            _handleTransfer(arcToken, taker, arcTraded - arcFee);
            _handleTransfer(arcToken, feeReceiver, arcFee);

            // Maker had locked ARC in the contract at order creation.
            // We only deduct the filled amount from the maker's locked collateral by reducing order.amount below.
        } else {
            // Maker placed a BUY ARC order (maker locked USDT collateral in contract).
            // Taker sells ARC by transferring ARC to contract.

            // 1. Taker transfers ARC for this partial fill
            _handleTransferFrom(arcToken, taker, address(this), arcTraded);

            // 2. Deliver net ARC to maker and taker fee to feeReceiver
            _handleTransfer(arcToken, maker, arcTraded - arcFee);
            _handleTransfer(arcToken, feeReceiver, arcFee);

            // 3. Pay taker in USDT from maker's collateral (contract balance), net of maker fee
            _handleTransfer(usdtToken, taker, usdtTraded - usdtFee);
            _handleTransfer(usdtToken, feeReceiver, usdtFee);
        }

        // Update remaining amount on the order
        order.amount = order.amount - amount;

        if (order.amount == 0) {
            order.status = Status.Executed;
        } else {
            // keep as Active for remaining amount (partial fill)
            order.status = Status.Active;
        }

        emit OrderFilled(orderId, maker, taker, amount, arcTraded, usdtTraded, arcFee, usdtFee);
    }

    /**
     * @notice Refunds the maker of a canceled order their collateral.
     * @dev The calling contract should ensure this is only called for canceled orders.
     */
    function _refundMaker(uint256 orderId, address account) internal {
        Order storage order = orders[orderId];
        uint256 refundAmount = order.amount;

        if (order.isSell) {
            _handleTransfer(arcToken, account, refundAmount);
        } else {
            // Refund USDT collateral
            uint256 usdtToRefund = (refundAmount * order.price) / (10 ** 18);
            _handleTransfer(usdtToken, account, usdtToRefund);
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
