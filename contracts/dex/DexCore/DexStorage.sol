// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {DexErrors} from "./DexErrors.sol";
import {IMultiAssetVault} from "../interfaces/IMultiAssetVault.sol";

/**
 * @title DexStorage
 * @dev This abstract contract defines the persistent state and data structures for the OrderBook.
 */
abstract contract DexStorage {
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
     * @param volumeFloor The minimum trade volume **in USDT** (quote token) required to qualify for this tier.
     * 10**18).
     * @param makerFeeBps The fee rate for makers in basis points (1 BPS = 0.01%).
     * @param takerFeeBps The fee rate for takers in basis points (1 BPS = 0.01%).
     */
    struct FeeTier {
        uint256 volumeFloor; // Minimum trade value in USDT (6 decimals, e.g. 1_000e6 = $1,000) to qualify for this tier
        uint16 makerFeeBps; // Fee in basis points (max 9999)
        uint16 takerFeeBps; // Fee in basis points (max 9999)
    }

    /**
     * @dev Represents a limit order placed in the book.
     * @param id Unique identifier.
     * @param maker The address that placed the order.
     * @param isSell True for Sell ARC, False for Buy ARC.
     * @param amount full amount of ARC to trade.
     * @param price Price: USDT (6 decimals) per 1 whole ARC (e.g., 2e6 = 2 USDT/ARC).
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

    /// @notice The ERC20 token being traded (e.g., ARC).
    address public arcToken;
    /// @notice The ERC20 token used for payment (e.g., USDT).
    address public usdtToken;

    /// @notice Indicates if the fee receiver address has been changed.
    bool public isFeeReceiverChanged;

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
     * @param _arcToken Address of the ARC ERC20 token.
     * @param _usdtToken Address of the USDT ERC20 token.
     * @param _feeReceiver Address to send the collected fees.
     */
    function __DexStorage_init(address _arcToken, address _usdtToken, address _feeReceiver, address _vault) internal {
        if (_arcToken == address(0) || _usdtToken == address(0) || _feeReceiver == address(0) || _vault == address(0)) {
            revert DexErrors.ZeroAddress();
        }
        if (_arcToken == _usdtToken) {
            revert DexErrors.SameTokens();
        }

        // --- Initialize Immutable State Variables ---
        arcToken = _arcToken;
        usdtToken = _usdtToken;
        feeReceiver = _feeReceiver;
        vault = IMultiAssetVault(_vault);
        nextOrderId = 1;

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
                volumeFloor: 1_000e6,
                makerFeeBps: 72, // 0.72%
                takerFeeBps: 90 // 0.90%
            })
        );

        // $5,000 - $40,000
        feeTiers.push(
            FeeTier({
                volumeFloor: 5_000e6,
                makerFeeBps: 64, // 0.64%
                takerFeeBps: 72 // 0.72%
            })
        );

        // $40,000 - $100,000
        feeTiers.push(
            FeeTier({
                volumeFloor: 40_000e6,
                makerFeeBps: 50, // 0.50%
                takerFeeBps: 68 // 0.68%
            })
        );

        // $100,000 - $1,000,000
        feeTiers.push(
            FeeTier({
                volumeFloor: 100_000e6,
                makerFeeBps: 40, // 0.40%
                takerFeeBps: 54 // 0.54%
            })
        );

        // Above $1,000,000
        feeTiers.push(
            FeeTier({
                volumeFloor: 1_000_000e6,
                makerFeeBps: 30, // 0.30%
                takerFeeBps: 48 // 0.48%
            })
        );
    }
}
