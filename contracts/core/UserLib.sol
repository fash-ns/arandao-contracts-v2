// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

library UserLib {
  /// @notice User data structure containing tree position and commission tracking
  struct User {
    uint256 parentId; // Parent user ID (0 for root)
    address userAddress; // Address of the user
    uint8 position; // Position under parent (0-3)
    bytes32[] path; // Encoded path from root to user
    uint256 lastCalculatedOrder; // Last processed order ID for this user
    uint256[4] childrenBv; // Accumulated BV for each direct childs of normal nodes position
    uint256[4] childrenAggregateBv; // Accumulated BV for each direct childs of normal nodes position. Aggregated
    uint256[2] normalNodesBv; // Accumulated BV for normal nodes
    uint256 bv; // User's total business volume
    uint256 eligibleDnmWithdrawWeekNo; // Week number when user could withdraw earned DNM (networker side)
    uint256 totalSteps; // User's total steps
    uint256 bvOnBridgeTime; // User's bv when the user is bridged
    uint256 fvEntranceMonth; // The month number where user entered fast value pool
    uint8 fvEntranceShare; // Could be 1 for half share and 2 for whole share
    uint256 networkerDnmShare; // The share of the user from minted DNM
    uint256 withdrawNetworkerDnmShareMonth; // The last month user has withdrawn his DNM share
    bool migrated; //True for users who are bridged from old smart contract
    uint256 withdrawableCommission; // User's earned commission available for withdrawal
    uint256 lastDnmWithdrawNetworkerWeekNumber; // User's last week number of DNM withdraw for networker
    uint256 lastDnmWithdrawUserWeekNumber; // User's last week number of DNM withdraw for user
    uint256 createdAt; // Block timestamp of registration
    bool active; // Whether user is active
  }

  /// @notice Emitted when a user is migrated
  /// @param userId The assigned user ID
  /// @param parentId The parent user ID
  /// @param position The position under parent (0-3)
  /// @param userAddr The user's EOA address
  event UserMigrated(
    uint256 indexed userId,
    uint256 indexed parentId,
    uint8 position,
    address indexed userAddr
  );
  /// @notice Emitted when a new user is registered
  /// @param userId The assigned user ID
  /// @param parentId The parent user ID
  /// @param position The position under parent (0-3)
  /// @param userAddr The user's EOA address
  event UserRegistered(
    uint256 indexed userId,
    uint256 indexed parentId,
    uint8 position,
    address indexed userAddr
  );

  /// @notice Emitted when a user changes their EOA address
  /// @param userId The user ID that changed their address
  /// @param oldAddress The previous EOA address
  /// @param newAddress The new EOA address
  event AddressChanged(
    uint256 indexed userId,
    address indexed oldAddress,
    address indexed newAddress
  );

  event AddressChangeRequested(
    uint256 userId,
    address oldAddress,
    address newAddress
  );

  error InvalidParentId();
  error InvalidPosition();
  error PositionAlreadyTaken();
  error UserAlreadyRegistered();
  error UserNotRegistered();

  error FirstUserMustBeRoot();
  error AddressAlreadyRegistered();
  error ParentInsufficientBVForPosition(uint8 position, uint256 parentBv);
  error InvalidParentAddress();
}
