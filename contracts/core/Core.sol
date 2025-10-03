// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {Users} from "./Users.sol";
import {Sellers} from "./Sellers.sol";
import {SellerLib} from "./SellerLib.sol";
import {Orders} from "./Orders.sol";
import {OrderLib} from "./OrderLib.sol";
import {UserLib} from "./UserLib.sol";
import {HelpersLib} from "./HelpersLib.sol";
import {Finance} from "./Finance.sol";
import {FastValue} from "./FastValue.sol";

/**
 * @title AranDAOPro - Multi-Level Marketing Binary Tree Contract
 * @notice Implements a secure, gas-conscious MLM tree structure with on-chain order bookkeeping
 * @dev Each node can have up to 4 children (positions 0-3). Path encoding uses bytes32 arrays
 *      where each byte represents a position (0x00-0x03). Supports efficient subtree calculations
 *      and commission tracking via lastCalculatedOrder mechanism.
 *
 * Path Encoding:
 * - Each bytes32 contains up to 32 path levels
 * - Each byte holds values 0x00, 0x01, 0x02, 0x03 representing positions 0-3
 * - When path exceeds 32 levels, new bytes32 is appended to array
 *
 * isSubTree Semantics:
 * - Returns (true, position) if candidate is in subtree via direct child at position
 * - Returns (true, 255) when candidate == root (sentinel value for same node)
 * - Returns (false, 0) if not in subtree
 */
contract AranDaoProCore is ReentrancyGuard, Users, Sellers, Orders, Finance, FastValue {
  /// @notice Amount data structure containing both SV and BV values
  struct Amount {
    address sellerAddress;
    uint256 sv; // Sales Volume
    uint256 bv; // Business Volume
  }
  /// @dev The timestamp of the contract deployment.
  uint256 public deploymentTs;

  /// @dev migration operator in the specified time
  address public migrationOperator;

  /// @notice Maps day to total global steps for that day
  mapping(uint256 => uint256) public globalDailySteps;

  /// @notice Maps day to flush-out counter for that day
  mapping(uint256 => uint256) public globalDailyFlushOuts;

  // Events

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

  event UserFlushedOut(uint256 indexed userId, uint256 indexed day);

  /// @notice Emitted when a user withdraws commission
  /// @param userId The user ID who withdrew
  /// @param amount The amount withdrawn
  event CommissionWithdrawn(uint256 indexed userId, uint256 amount);

  // Custom errors
  error InsufficientBVForNewUser();
  error UserHasNoFastValueShares();
  error UserHasAlreadyWithdrawnFastValueShare();

  modifier onlyOperator() {
    require(
      deploymentTs + 7 days > block.timestamp,
      "The time for migration has been passed."
    );
    require(
      msg.sender == migrationOperator,
      "Sender address is not eligible to migrate."
    );
    _;
  }

  constructor(
    address _migrationOperator,
    address _dnmAddress,
    address _paymentTokenAddress,
    address _vaultAddress
  ) Finance(_paymentTokenAddress, _dnmAddress, _vaultAddress) {
    deploymentTs = block.timestamp;
    migrationOperator = _migrationOperator;
  }

  /**
   * @notice Registers a new user in the MLM tree
   * @dev First user must have parentId=0 and position=0. All others need valid parent.
   *      Path is computed by copying parent's path and appending new position.
   * @param userAddr The EOA address to register
   * @param parentId The parent user ID (0 for root user only)
   * @param position The position under parent (0-3)
   */
  function migrateUser(
    address userAddr,
    uint256 parentId,
    uint8 position,
    uint256 bv,
    uint256 withdrawableCommission,
    uint256[4] memory childrenSafeBv,
    uint256[4] memory childrenAggregateBv
  ) external onlyOperator {
    _migrateUser(
      userAddr,
      parentId,
      position,
      bv,
      withdrawableCommission,
      childrenSafeBv,
      childrenAggregateBv,
      lastOrderId
    );
  }

  /**
   * @notice Creates new orders for commission calculation
   * @dev Buyer and seller will be automatically registered if they don't exist.
   *      For new users, total BV must be greater than 100 ether.
   * @param buyerAddress The buyer's EOA address
   * @param parentAddress The parent's EOA address (for user creation)
   * @param position The position under parent (0-3, for user creation)
   * @param amounts Array of Amount structs containing SV and BV values
   */
  //TODO: Add whitelist contract
  function createOrder(
    address buyerAddress,
    address parentAddress,
    uint8 position,
    Amount[] calldata amounts
  ) external {
    require(amounts.length > 0, "At least one amount required");

    bool isUserExisted = _userExistsByAddress(buyerAddress);

    uint256 totalBv = 0;
    for (uint256 i = 0; i < amounts.length; i++) {
      totalBv += amounts[i].bv;
    }

    // If new user, validate minimum BV requirement
    if (!isUserExisted) {
      if (totalBv < 100 ether) revert InsufficientBVForNewUser();
    }

    uint256 buyerId = _getOrCreateUser(
      buyerAddress,
      parentAddress,
      position,
      lastOrderId
    );
    uint256 weekNumber = HelpersLib.getWeekOfTs(block.timestamp);

    // Process each amount and create orders
    for (uint256 i = 0; i < amounts.length; i++) {
      uint256 sellerId = _getOrCreateSeller(amounts[i].sellerAddress);

      _createOrder(buyerId, sellerId, amounts[i].sv, amounts[i].bv);
      _addSellerBv(sellerId, weekNumber, amounts[i].bv);
    }

    _addUserBv(buyerId, weekNumber, totalBv);
    _addTotalWeekBv(weekNumber, totalBv);
    _addMonthlyFv(totalBv * 2 / 10); // FV = 20% * BV;

    UserLib.User storage user = _getUserById(buyerId);

    //Add user to fast value if conditions are passed.
    if (!user.migrated && user.fvEntranceMonth != 0) {
      uint256 month = HelpersLib.getMonth(block.timestamp);
      if (user.fvEntranceMonth + 12 > month) {
        for (uint8 i = 1; i < 12; i++) {
          uint256 requiredBvForFastValue = 100 ether * (12 ** i) / (10 ** i);
          if (user.bv < requiredBvForFastValue) {
            break;
          }
          _submitUserForFastValue(buyerId, user.fvEntranceMonth + i, user.fvEntranceShare);
        }
      }
    }
  }

  function withdrawFastValueShare() public {
    uint256 userId = _getUserIdByAddress(msg.sender);
    uint256 month = HelpersLib.getMonth(block.timestamp);

    uint8 userShare = monthlyUserShares[month][userId];
    bool isWithdrawm = monthlyUserShareWithdraws[month][userId];

    if (userShare == 0) {
      revert UserHasNoFastValueShares();
    }

    if (isWithdrawm) {
      revert UserHasAlreadyWithdrawnFastValueShare();
    }

    uint256 pastMonth = HelpersLib.getMonth(block.timestamp) - 1;
    uint256 userFvShare = _getUserShare(userId, pastMonth);

    bool isPaymentSuccessful = _transferPaymentToken(msg.sender, userFvShare);

    require(isPaymentSuccessful, "Token payment error");

    monthlyUserShareWithdraws[pastMonth][userId] = true;
  }

  /**
   * @notice Processes orders for commission calculation with gas limit protection
   * @dev Iterates through orders starting from lastCalculatedOrder + 1, updating
   *      childrenBv for direct children whose subtrees contain the buyers
   * @param callerId The user ID to calculate commissions for
   * @param orderIds Array of proccessable orderIds.
   */
  function calculateOrders(
    uint256 callerId,
    uint256[] memory orderIds
  ) external nonReentrant {
    UserLib.User storage user = _getUserById(callerId);

    uint256 lastCalculatedOrderDate = _getOrderById(user.lastCalculatedOrder)
      .createdAt;

    uint16 orderIdsLen = uint16(orderIds.length);

    require(
      orderIdsLen < 255,
      "100 orders can be proccessed in a single transaction as most."
    );

    for (uint8 i = 0; i < orderIdsLen; i++) {
      require(
        orderIds[i] > user.lastCalculatedOrder,
        "Order with greater ID is already processed for this user."
      );

      OrderLib.Order memory order = _getOrderById(orderIds[i]);

      //TODO: Handle weekly calculate logic.
      //TODO: Handle flush-out for the rest of the time interval.
      if (
        HelpersLib.getDayOfTs(lastCalculatedOrderDate) <
        HelpersLib.getDayOfTs(order.createdAt)
      ) {
        calculateDailyCommission(
          callerId,
          HelpersLib.getDayOfTs(lastCalculatedOrderDate)
        );
      }

      (bool inSubTree, uint8 childPosition) = _isSubTree(
        callerId,
        order.buyerId
      );

      if (inSubTree && childPosition != SAME_NODE_SENTINEL) {
        // Accumulate BV update for the direct child position
        user.childrenBv[childPosition] += order.bv;
        user.normalNodesBv[childPosition / 2] += order.bv;
      }

      lastCalculatedOrderDate = order.createdAt;
    }

    user.lastCalculatedOrder = orderIds[orderIdsLen - 1];

    emit OrdersCalculated(callerId, orderIdsLen, orderIds[orderIdsLen - 1]);
  }

  /**
   * @notice Calculates daily commission for a specific user based on their BV pairs
   * @dev Processes 3 pairs: childrenBv[0-1], childrenBv[2-3], and normalNodesBv[0-1]
   *      Each pair can have max 6 steps per day. At 6 steps, both sides are flushed to 0.
   * @param userId The user ID to calculate commission for
   */
  function calculateDailyCommission(
    uint256 userId,
    uint256 lastOrderTimestamp
  ) internal {
    UserLib.User storage user = _getUserById(userId);
    uint256 dayNumber = HelpersLib.getDayOfTs(lastOrderTimestamp);
    uint256 totalUserCommissionEarned = 0;

    // Process 3 pairs
    for (uint8 pairIndex = 0; pairIndex < 3; pairIndex++) {
      (uint256 leftBv, uint256 rightBv) = _getUserPairByIndex(
        userId,
        pairIndex
      );

      uint8 currentSteps = _getUserDailySteps(userId, dayNumber, pairIndex);

      // Process steps while both sides >= 500 ether and steps < 6
      while (leftBv >= 500 ether && rightBv >= 500 ether && currentSteps < 6) {
        // Subtract 500 ether from both sides
        leftBv -= 500 ether;
        rightBv -= 500 ether;

        // Add 60 ether commission
        totalUserCommissionEarned += 60 ether;

        // Increment counters
        currentSteps++;
        globalDailySteps[dayNumber]++;
      }

      if (currentSteps > 0) {
        checkUserAuthorityForFvEntrance(userId);
      }

      _setUserPairByIndex(userId, leftBv, rightBv, pairIndex);

      // Update daily steps for this pair
      _setUserDailySteps(userId, dayNumber, pairIndex, currentSteps + 1);

      // Check for flush-out (6 steps reached)
      if (currentSteps == 6) {
        // Set both sides to 0 (discard excess BV)
        _setUserPairByIndex(userId, 0, 0, pairIndex);
        globalDailyFlushOuts[dayNumber]++;

        emit UserFlushedOut(userId, dayNumber);
      }

      emit DailyCommissionCalculated(
        userId,
        dayNumber,
        totalUserCommissionEarned,
        pairIndex,
        currentSteps
      );
    }

    totalCommissionEarned += totalUserCommissionEarned;
    // Add earned commission to user's withdrawable balance
    user.withdrawableCommission += totalUserCommissionEarned;
  }

  function checkUserAuthorityForFvEntrance(uint256 userId) internal {
    UserLib.User storage user = _getUserById(userId);
    if (!user.migrated) {
      uint256 month = HelpersLib.getMonth(block.timestamp);
      if (user.createdAt + 30 days > block.timestamp) {
        _submitUserForFastValue(userId, month, 2);
      } else if (user.createdAt + 60 days > block.timestamp) {
        _submitUserForFastValue(userId, month, 1);
      }
    }
  }

  /**
   * @notice Allows a user to withdraw their accumulated commission
   * @param amount The amount to withdraw
   */
  function withdrawCommission(uint256 amount) external nonReentrant {
    uint256 userId = _getUserIdByAddress(msg.sender);
    UserLib.User storage user = _getUserById(userId);
    require(
      amount <= user.withdrawableCommission,
      "Insufficient commission balance"
    );

    bool isTxSuccessful = _transferPaymentToken(msg.sender, amount);

    require(isTxSuccessful, "Error while transfering payment token to user");

    user.withdrawableCommission -= amount;
    totalCommissionEarned -= amount;

    emit CommissionWithdrawn(userId, amount);
  }

  function mintWeeklyDnm() public {
    _mintWeeklyDnm();
  }

  function calculateNetworkerWeeklyDnm() public {
    uint256 userId = _getUserIdByAddress(msg.sender);
    UserLib.User storage user = users[userId];
    uint256 passedWeekNumber = HelpersLib.getWeekOfTs(block.timestamp) - 1;

    if (passedWeekNumber > dnmMintWeekNumber) {
      mintWeeklyDnm();
    }

    require(
      user.lastDnmWithdrawNetworkerWeekNumber < passedWeekNumber,
      "Networker has already calculated DNM for this week."
    );

    uint256 userWeekSteps = 0;
    uint256 totalWeekSteps = 0;

    for (uint8 i = 0; i < 7; i++) {
      uint256 dayNumber = (passedWeekNumber) * 7 + i;
      totalWeekSteps = globalDailySteps[dayNumber];
      for (uint8 j = 0; j < 3; j++) {
        userWeekSteps += _getUserDailySteps(userId, dayNumber, j);
      }
    }

    uint256 networkerDnmShare = (((lastWeekDnmMintAmount * 60) / 100) *
      userWeekSteps) / totalWeekSteps;

    totalDnmEarned += ((networkerDnmShare * 30) / 100);
    user.networkerDnmShare += ((networkerDnmShare * 30) / 100);

    _transferDnm(msg.sender, (networkerDnmShare * 70) / 100);

    //TODO: Add calculated event
  }

  function calculateUserWeeklyDnm() public {
    uint256 userId = _getUserIdByAddress(msg.sender);
    UserLib.User storage user = users[userId];
    uint256 passedWeekNumber = HelpersLib.getWeekOfTs(block.timestamp) - 1;

    if (passedWeekNumber > dnmMintWeekNumber) {
      mintWeeklyDnm();
    }

    require(
      user.lastDnmWithdrawUserWeekNumber < passedWeekNumber,
      "User has already calculated DNM for this week."
    );

    uint256 userDnmShare = (((lastWeekDnmMintAmount * 35) / 100) *
      _getUserWeeklyBv(userId, passedWeekNumber)) /
      _getWeeklyBv(passedWeekNumber);

    _transferDnm(msg.sender, userDnmShare);

    //TODO: Add calculated event
  }

  function calculateSellerWeeklyDnm() public {
    uint256 sellerId = _getSellerIdByAddress(msg.sender);
    SellerLib.Seller storage seller = _getSellerById(sellerId);
    uint256 passedWeekNumber = HelpersLib.getWeekOfTs(block.timestamp) - 1;

    if (passedWeekNumber > dnmMintWeekNumber) {
      mintWeeklyDnm();
    }

    require(
      seller.lastDnmWithdrawWeekNumber < passedWeekNumber,
      "Seller has already calculated DNM for this week."
    );

    uint256 sellerDnmShare = (((lastWeekDnmMintAmount * 5) / 100) *
      sellerWeeklyBv[sellerId][passedWeekNumber]) /
      _getWeeklyBv(passedWeekNumber);

    _transferDnm(msg.sender, sellerDnmShare); //TODO: Change the percent

    //TODO: Add calculated event
  }

  function monthlyWithdrawNetworkerDnm() public {
    uint256 userId = _getUserIdByAddress(msg.sender);
    UserLib.User storage user = users[userId];

    uint256 month = HelpersLib.getMonth(block.timestamp);
    require(
      month >= user.withdrawNetworkerDnmShareMonth + 3,
      "User has already withdrawn DNM share for this 3 month period"
    );

    uint256 dnmAmount = (user.networkerDnmShare * 25) / 100;
    _transferDnm(msg.sender, dnmAmount);

    user.networkerDnmShare -= dnmAmount;
    user.withdrawNetworkerDnmShareMonth = month;
    totalDnmEarned -= dnmAmount;

    //TODO: Add withdraw event
  }

  function requestChangeAddress(address newAddress) public {
    _requestChangeAddress(msg.sender, newAddress);
  }

  function approveChangeAddress(uint256 userId) public {
    _approveChangeAddress(msg.sender, userId);
  }
}
