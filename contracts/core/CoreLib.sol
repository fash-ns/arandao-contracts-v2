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

  /// @notice Emitted when DNM share is calculated for networker
  event NetworkerDnmShareCalculated(
    uint256 indexed userId,
    uint256 indexed week,
    uint256 share
  );

  /// @notice Emitted when DNM share is calculated for user
  event UserDnmShareCalculated(
    uint256 indexed userId,
    uint256 indexed week,
    uint256 share
  );

  /// @notice Emitted when DNM share is calculated for seller
  event SellerDnmShareCalculated(
    uint256 indexed sellerId,
    uint256 indexed week,
    uint256 share
  );

  /// @notice Emitted when monthly DNM share is withdrawn by networker
  event NetworkerMonthlyDnmShareWithdrawn(
    uint256 indexed userId,
    uint256 indexed daysPeriod,
    uint256 share
  );

  event UserDailyFlushedOut(uint256 indexed userId, uint256 indexed day);
  event UserWeeklyFlushedOut(uint256 indexed userId, uint256 indexed week);

  /// @notice Emitted when a user withdraws commission
  /// @param userId The user ID who withdrew
  /// @param amount The amount withdrawn
  event CommissionWithdrawn(uint256 indexed userId, uint256 amount);

  event MonthlyFastValueWithdrawn(uint256 userId, uint256 month, uint256 share);

  // Custom errors
  error InsufficientBVForNewUser();
  error UserHasNoFastValueShares();
  error UserHasAlreadyWithdrawnFastValueShare();
}
