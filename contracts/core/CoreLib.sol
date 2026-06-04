// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

library CoreLib {
  /// @notice Emitted when orders are processed for commission calculation
  /// @param userId The user ID for whom orders were calculated
  /// @param processed Number of orders processed in this call
  /// @param lastCalculatedOrder New value of lastCalculatedOrder for this user
  event OrdersCalculated(
    uint256 indexed userId,
    uint256 processed,
    uint256 lastCalculatedOrder
  );

  /// @notice Emitted when daily commission is calculated for a user
  /// @param userId The user ID for whom commission was calculated
  /// @param day The day (timestamp / 86400) for the calculation
  /// @param totalCommission The total commission amount earned
  /// @param pairProcessed The number of pairs that had steps processed
  event DailyCommissionCalculated(
    uint256 indexed userId,
    uint256 indexed day,
    uint256 totalCommission,
    uint8 pairProcessed,
    uint256 steps
  );

  /// @notice Emitted when owner changes fee receiver address
  /// @param newAddress The new fee receiver address
  event FeeReceiverChanged(address newAddress);

  /// @notice Emitted when dev mode is revoked
  event DevModeRevoked();

  /// @notice Emitted when daily commission is calculated for a user
  /// @param userId The user ID for whom commission was calculated
  /// @param week The week (timestamp / 86400 / 7) for the calculation
  /// @param totalCommission The total commission amount earned
  /// @param pairProcessed The number of pairs that had steps processed
  event WeeklyCommissionCalculated(
    uint256 indexed userId,
    uint256 indexed week,
    uint256 totalCommission,
    uint8 pairProcessed,
    uint256 steps
  );

  /// @notice Emitted when ARC share is calculated for networker
  event NetworkerArcShareCalculated(
    uint256 indexed userId,
    uint256 indexed week,
    uint256 share
  );

  /// @notice Emitted when ARC share is calculated for user
  event UserArcShareCalculated(
    uint256 indexed userId,
    uint256 indexed week,
    uint256 share
  );

  /// @notice Emitted when ARC share is calculated for seller
  event SellerArcShareCalculated(
    uint256 indexed sellerId,
    uint256 indexed week,
    uint256 share
  );

  event UserDailyFlushedOut(uint256 indexed userId, uint256 indexed day);
  event UserWeeklyFlushedOut(uint256 indexed userId, uint256 indexed week);

  /// @notice Emitted when a user withdraws commission
  /// @param userId The user ID who withdrew
  /// @param amount The amount withdrawn
  event CommissionWithdrawn(uint256 indexed userId, uint256 amount);

  /// @notice Emitted when oracle, yield pool, and fast value addresses are configured
  event AddressesSet(
    address twapAddress,
    address yieldPoolAddress,
    address fastValueAddress
  );

  /// @notice Emitted when a user becomes eligible for networker ARC withdrawal
  event EligibleArcWithdrawWeekSet(
    uint256 indexed userId,
    uint256 indexed weekNumber
  );

  // Custom errors
  error InsufficientBVForNewUser();
}
