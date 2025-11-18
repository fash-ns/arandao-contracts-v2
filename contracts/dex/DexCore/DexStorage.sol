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
     * @param volumeFloor The minimum initial DNM amount (scaled by 1e18) to qualify for this tier.
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
    address public immutable dnmToken;
    /// @notice The ERC20 token used for payment (e.g., DAI).
    address public immutable daiToken;
    /// @notice The address that receives the trading fees.
    address public immutable feeReceiver;

    /// @notice The vault contract for secure token transfers.
    IMultiAssetVault internal immutable vault;

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
     * @param _feeTiers List of initial fee tiers (volumeFloor, feeBps).
     */
    constructor(
        address _dnmToken,
        address _daiToken,
        address _feeReceiver,
        address _vault,
        FeeTier[] memory _feeTiers
    ) {
        if (
            _dnmToken == address(0) ||
            _daiToken == address(0) ||
            _feeReceiver == address(0)
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

        // --- Fee Tier Validation and Storage Assignment ---
        if (_feeTiers.length == 0) {
            revert DexErrors.InvalidTierConfiguration();
        }

        // Validate structure (ascending volumeFloor and max fee)
        for (uint256 i = 0; i < _feeTiers.length; i++) {
            FeeTier memory currentTier = _feeTiers[i];

            // Check max fee rate (10000 BPS = 100%)
            if (
                currentTier.makerFeeBps >= 10000 ||
                currentTier.takerFeeBps >= 10000
            ) {
                revert DexErrors.FeeTooHigh();
            }

            if (i > 0) {
                if (currentTier.volumeFloor <= _feeTiers[i - 1].volumeFloor) {
                    revert DexErrors.InvalidTierConfiguration();
                }
            }

            feeTiers.push(currentTier);
        }

        nextOrderId = 1;
    }
}
