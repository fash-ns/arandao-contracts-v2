// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {Users} from "./Users.sol";
import {Sellers} from "./Sellers.sol";
import {SellerLib} from "./SellerLib.sol";
import {Orders} from "./Orders.sol";
import {OrderLib} from "./OrderLib.sol";
import {UserLib} from "./UserLib.sol";
import {HelpersLib} from "./HelpersLib.sol";
import {Finance} from "./Finance.sol";
import {FastValue} from "./FastValue.sol";
import {CalculationLogic} from "./CalculationLogic.sol";
import {CoreLib} from "./CoreLib.sol";
import {SecurityGuard} from "./SecurityGuard.sol";

import {console} from "forge-std/console.sol"; //TODO: Remove

/**
 * @title AranDAOPro - Multi-Level Marketing Binary Tree Contract
 * @author Farbod Shams <farbodshams.2000@gmail.com>
 * @notice Implements a secure, gas-conscious MLM tree structure with on-chain order bookkeeping
 * @dev Each node can have up to 4 children (positions 0-3). Path encoding uses bytes32 arrays
 *      where each byte represents a position (0x00-0x03). Supports efficient subtree calculations
 *      and commission tracking via lastCalculatedOrder mechanism.
 */
contract AranCore is
  ReentrancyGuard,
  Users,
  Sellers,
  Orders,
  Finance,
  FastValue,
  CalculationLogic,
  SecurityGuard
{
  /// @notice Amount data structure containing both SV and BV values
  struct Amount {
    address sellerAddress;
    uint256 sv; // Sales Volume
    uint256 bv; // Business Volume
  }

  struct MigrateUserData {
    address userAddr;
    address parentAddr;
    uint8 position;
    uint256 bv;
    uint256[4] childrenSafeBv;
    uint256[4] childrenAggregateBv;
    uint256[2] normalNodesBv;
  }

  /// @notice Maps day to total global steps for that day
  mapping(uint256 => uint256) globalDailySteps;

  /// @notice Maps day to flush-out counter for that day
  mapping(uint256 => uint256) globalDailyFlushOuts;

  uint256 totalDnmWeeklySteps;

  constructor(
    address _dnmAddress,
    address _paymentTokenAddress
  )
    Finance(_paymentTokenAddress, _dnmAddress)
    SecurityGuard()
  {
  }


  function emergencyWithdraw() public {
    require(msg.sender == owner, "Only owner can withdraw");
    require(deploymentTs + 120 >= block.timestamp, "Time of withdraw has been passed"); //TODO: Change to 90 days

    IERC20 paymentToken = IERC20(paymentTokenAddress);
    paymentToken.transfer(owner, paymentToken.balanceOf(address(this)));
  }

  function setVaultAddress(address _vaultAddress) public onlyManager {
    require(vaultAddress == address(0), "Vault address is already set");
    vaultAddress = _vaultAddress;
  }

  /**
   * @notice Registers a new user in the MLM tree
   * @dev First user must have parentId=0 and position=0. All others need valid parent.
   *      Path is computed by copying parent's path and appending new position.
   * @param data An array of MigrateUserData struct
   */
  function migrateUser(MigrateUserData[] calldata data) external onlyMigrateOperator {
    uint256 len = data.length;
    
    for (uint256 i = 0; i < len; i++) {
      _migrateUser(
        data[i].userAddr,
        data[i].parentAddr,
        data[i].position,
        data[i].bv,
        data[i].childrenSafeBv,
        data[i].childrenAggregateBv,
        data[i].normalNodesBv,
        lastOrderId
      );
    }
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

  function createOrder(
    address buyerAddress,
    address parentAddress,
    uint8 position,
    Amount[] calldata amounts,
    uint256 totalAmount
  ) external onlyOrderCreatorContracts(msg.sender) {
    require(amounts.length > 0, "At least one amount required");

    bool isUserExisted = _userExistsByAddress(buyerAddress);

    uint256 totalBv = 0;
    for (uint256 i = 0; i < amounts.length; i++) {
      totalBv += amounts[i].bv;
    }

    require(totalAmount >= totalBv, "Provided amount is less than order business amounts");

    IERC20 paymentToken = IERC20(paymentTokenAddress);
    bool isPaymentSuccessful = paymentToken.transferFrom(msg.sender, address(this), totalAmount);
    require(isPaymentSuccessful, "Transfer token from the market contract wasn't successful");

    uint256 minBv = _getMinBv();

    // If new user, validate minimum BV requirement
    if (!isUserExisted) {
      if (totalBv < minBv) revert CoreLib.InsufficientBVForNewUser();
    }

    uint256 buyerId = _getOrCreateUser(
      buyerAddress,
      parentAddress,
      position,
      lastOrderId,
      minBv
    );
    uint256 weekNumber = HelpersLib.getWeekOfTs(block.timestamp);
    console.log("Week number is: %d", weekNumber);

    // Process each amount and create orders
    for (uint256 i = 0; i < amounts.length; i++) {
      _createOrderLoop(amounts[i], buyerId, weekNumber);
    }

    _addUserBv(buyerId, weekNumber, totalBv);
    _addTotalWeekBv(weekNumber, totalBv);
    console.log("Current total weekly BV is: %d", _getWeeklyBv(weekNumber));
    _addMonthlyFv((totalBv * 20) / 100); // FV = 20% * BV;

    UserLib.User storage user = _getUserById(buyerId);

    //Add user to fast value if conditions are passed.
    if (!user.migrated && user.fvEntranceMonth != 0) {
      uint256 month = HelpersLib.getMonth(block.timestamp);
      if (user.fvEntranceMonth + 12 > month) {
        for (uint8 i = 1; i < 12; i++) {
          uint256 requiredBvForFastValue = ((minBv * (12 ** i)) / (10 ** i));
          if (user.bv < requiredBvForFastValue) {
            break;
          }
          _submitUserForFastValue(
            buyerId,
            user.fvEntranceMonth + i,
            user.fvEntranceShare
          );
        }
      }
    }
  }

  function _createOrderLoop(Amount calldata amount, uint256 buyerId, uint256 weekNumber) internal {
      uint256 sellerId = _getOrCreateSeller(amount.sellerAddress);

      _createOrder(buyerId, sellerId, amount.sv, amount.bv);
      _addSellerBv(sellerId, weekNumber, amount.bv);
  }

  function withdrawFastValueShare(uint256 selectedMonth) public nonReentrant {
    uint256 userId = getUserIdByAddress(msg.sender);
    uint256 pastMonth = HelpersLib.getMonth(block.timestamp) - 1;

    require(selectedMonth <= pastMonth, "User cannot withdraw current or upcoming month share.");

    uint8 userShare = monthlyUserShares[selectedMonth][userId];
    bool isWithdrawn = monthlyUserShareWithdraws[selectedMonth][userId];

    if (userShare == 0) {
      revert CoreLib.UserHasNoFastValueShares();
    }

    if (isWithdrawn) {
      revert CoreLib.UserHasAlreadyWithdrawnFastValueShare();
    }

    uint256 userFvShare = _getUserShare(userId, selectedMonth);

    monthlyUserShareWithdraws[selectedMonth][userId] = true;

    bool isPaymentSuccessful = _transferPaymentToken(msg.sender, userFvShare);

    require(isPaymentSuccessful, "Token payment error");


    emit CoreLib.MonthlyFastValueWithdrawn(userId, selectedMonth, userFvShare);
  }

  /**
   * @notice Processes orders for commission calculation with gas limit protection
   * @dev Iterates through orders starting from lastCalculatedOrder + 1, updating
   *      childrenBv for direct children whose subtrees contain the buyers
   * @param callerId The user ID to calculate commissions for
   * @param orderIds Array of processable orderIds.
   */
  function calculateOrders(
    uint256 callerId,
    uint256[] memory orderIds
  ) external onlyManager {
    UserLib.User storage user = _getUserById(callerId);

    uint256 lastCalculatedOrderDate = 0;

    if (user.lastCalculatedOrder > 0) {
      lastCalculatedOrderDate = _getOrderById(user.lastCalculatedOrder)
      .createdAt;
    }

    uint16 orderIdsLen = uint16(orderIds.length);

    for (uint8 i = 0; i < orderIdsLen; i++) {
      require(
        orderIds[i] > user.lastCalculatedOrder,
        "Order with greater ID is already processed for this user."
      );

      OrderLib.Order memory order = _getOrderById(orderIds[i]);

      if (
        weeklyCalculationStartTime > 0 &&
        weeklyCalculationStartTime < block.timestamp
      ) {
        require(
          HelpersLib.getWeekOfTs(order.createdAt) <
            HelpersLib.getWeekOfTs(block.timestamp),
          "Cannot process orders from current week."
        );

        if (
          HelpersLib.getWeekOfTs(lastCalculatedOrderDate) <
          HelpersLib.getWeekOfTs(order.createdAt)
        ) {
          calculateWeeklyCommission(callerId, lastCalculatedOrderDate);
        }
      } else {
        require(
          HelpersLib.getDayOfTs(order.createdAt) <
            HelpersLib.getDayOfTs(block.timestamp),
          "Cannot process orders from current day."
        );

        if (
          HelpersLib.getDayOfTs(lastCalculatedOrderDate) <
          HelpersLib.getDayOfTs(order.createdAt)
        ) {
          calculateDailyCommission(callerId, lastCalculatedOrderDate);
        }
      }

      (bool inSubTree, uint8 childPosition) = _isSubTree(
        callerId,
        order.buyerId
      );

      if (inSubTree && childPosition != SAME_NODE_SENTINEL) {
        // Accumulate BV update for the direct child position
        user.childrenBv[childPosition] += order.bv;
        user.childrenAggregateBv[childPosition] += order.bv;
        user.normalNodesBv[childPosition / 2] += order.bv;
      }

      lastCalculatedOrderDate = order.createdAt;
    }

    user.lastCalculatedOrder = orderIds[orderIdsLen - 1];
    
    if (
        weeklyCalculationStartTime > 0 &&
        weeklyCalculationStartTime < block.timestamp
      ) {
        calculateWeeklyCommission(callerId, lastCalculatedOrderDate);
      } else {
        calculateDailyCommission(callerId, lastCalculatedOrderDate);
      }

    if (HelpersLib._isFirstDayOfWeek(block.timestamp)) {
      user.eligibleDnmWithdrawWeekNo =
        HelpersLib.getWeekOfTs(block.timestamp) - 1;
    }

    emit CoreLib.OrdersCalculated(
      callerId,
      orderIdsLen,
      orderIds[orderIdsLen - 1]
    );
  }

  /**
   * @notice Internal shared logic for daily/weekly commission calculation
   * @param userId The user ID to calculate commission for
   * @param periodDayNumber Day identifier used for step tracking
   *        - For daily: actual day number
   *        - For weekly: start day of the week (weekNumber * 7)
   * @param isWeekly Whether calculation is for weekly period
   * @param lastOrderTimestamp Timestamp of the last processed order (used for daily activation threshold)
   */
  function _calculateCommissionForPeriod(
    uint256 userId,
    uint256 periodDayNumber,
    bool isWeekly,
    uint256 lastOrderTimestamp
  ) internal {
    UserLib.User storage user = _getUserById(userId);
    uint256 totalUserCommissionEarned = 0;

    //TODO: Why user should provide orderIds from past time period.

    for (uint8 pairIndex = 0; pairIndex < 3; pairIndex++) {
      (uint256 leftBv, uint256 rightBv) = _getUserPairByIndex(
        userId,
        pairIndex
      );

      uint8 currentSteps = _getUserDailySteps(
        userId,
        periodDayNumber,
        pairIndex
      );

      uint256 bvBalance = _getBvBalance();
      uint256 maxSteps = _getMaxSteps();
      uint256 commissionPerStep = _getCommissionPerStep();

      while (
        leftBv >= bvBalance && rightBv >= bvBalance && currentSteps < maxSteps
      ) {
        leftBv -= bvBalance;
        rightBv -= bvBalance;

        totalUserCommissionEarned += commissionPerStep;

        currentSteps++;
        if (pairIndex == 2) {
          user.superNodeTotalSteps += 1;
        }
        globalDailySteps[periodDayNumber]++;
      }

      _setUserPairByIndex(userId, leftBv, rightBv, pairIndex);

      _setUserDailySteps(userId, periodDayNumber, pairIndex, currentSteps);

      if (currentSteps == maxSteps) {
        _setUserPairByIndex(userId, 0, 0, pairIndex);
        globalDailyFlushOuts[periodDayNumber]++;

        if (isWeekly) {
          emit CoreLib.UserWeeklyFlushedOut(userId, periodDayNumber / 7);
        } else {
          if (globalDailyFlushOuts[periodDayNumber] >= 1) { //TODO: Change to 95
            _activateWeeklyCalculation(lastOrderTimestamp);
          }
          emit CoreLib.UserDailyFlushedOut(userId, periodDayNumber);
        }
      }

      if (isWeekly) {
        emit CoreLib.WeeklyCommissionCalculated(
          userId,
          periodDayNumber / 7,
          totalUserCommissionEarned,
          pairIndex,
          currentSteps
        );
      } else {
        emit CoreLib.DailyCommissionCalculated(
          userId,
          periodDayNumber,
          totalUserCommissionEarned,
          pairIndex,
          currentSteps
        );
      }
    }

    // Two steps and check if user has the authority to join to FV vault.
    if (user.superNodeTotalSteps > 1) {
      checkUserAuthorityForFvEntrance(userId, lastOrderTimestamp);
    }

    totalCommissionEarned += totalUserCommissionEarned;
    user.withdrawableCommission += totalUserCommissionEarned;
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
    uint256 dayNumber = HelpersLib.getDayOfTs(lastOrderTimestamp);
    _calculateCommissionForPeriod(userId, dayNumber, false, lastOrderTimestamp);
  }

  /**
   * @notice Calculates weekly commission for a specific user based on their BV pairs
   * @dev Processes 3 pairs: childrenBv[0-1], childrenBv[2-3], and normalNodesBv[0-1]
   *      Each pair can have max 6 steps per day. At 6 steps, both sides are flushed to 0.
   * @param userId The user ID to calculate commission for
   */
  function calculateWeeklyCommission(
    uint256 userId,
    uint256 lastOrderTimestamp
  ) internal {
    uint256 dayNumber = HelpersLib.getWeekOfTs(lastOrderTimestamp) * 7;
    _calculateCommissionForPeriod(userId, dayNumber, true, lastOrderTimestamp);
  }

  function checkUserAuthorityForFvEntrance(uint256 userId, uint256 orderDate) internal {
    UserLib.User storage user = _getUserById(userId);
    if (!user.migrated) {
      uint256 month = HelpersLib.getMonth(orderDate);
      if (user.createdAt + 30 > orderDate) { //TODO: Change to 30 days
        _submitUserForFastValue(userId, month, 2);
        user.fvEntranceMonth = month;
        user.fvEntranceShare = 2;
      } else if (user.createdAt + 60 > orderDate) { //TODO: Change to 60 days
        _submitUserForFastValue(userId, month, 1);
        user.fvEntranceMonth = month;
        user.fvEntranceShare = 1;
      }
    }
  }

  /**
   * @notice Allows a user to withdraw their accumulated commission
   * @param amount The amount to withdraw
   */
  function withdrawCommission(uint256 amount) external nonReentrant {
    uint256 userId = getUserIdByAddress(msg.sender);
    UserLib.User storage user = _getUserById(userId);
    require(
      amount <= user.withdrawableCommission,
      "Insufficient commission balance"
    );

    user.withdrawableCommission -= amount;
    totalCommissionEarned -= amount;

    bool isTxSuccessful = _transferPaymentToken(msg.sender, amount);

    require(isTxSuccessful, "Error while transferring payment token to user");

    emit CoreLib.CommissionWithdrawn(userId, amount);
  }

  function mintWeeklyARC() public {
    require(
      !HelpersLib._isFirstDayOfWeek(block.timestamp),
      "ARC calculation is not possible at the first day of week."
    );

    uint256 passedWeekNumber = HelpersLib.getWeekOfTs(block.timestamp) - 1;
    uint256 totalWeekSteps = 0;

    for (uint8 i = 0; i < 7; i++) {
      uint256 dayNumber = (passedWeekNumber) * 7 + i;
      totalWeekSteps += globalDailySteps[dayNumber];
    }

    totalDnmWeeklySteps = totalWeekSteps;

    _mintWeeklyDnm();
  }

  function calculateNetworkerWeeklyARC() public nonReentrant {
    uint256 userId = getUserIdByAddress(msg.sender);
    UserLib.User storage user = users[userId];
    uint256 passedWeekNumber = HelpersLib.getWeekOfTs(block.timestamp) - 1;

    require(
      !HelpersLib._isFirstDayOfWeek(block.timestamp),
      "DNM calculation is not possible at the first day of week."
    );
    require(
      user.eligibleDnmWithdrawWeekNo == passedWeekNumber,
      "User hasn't calculated orders at the first day of the week."
    );

    if (passedWeekNumber > dnmMintWeekNumber) {
      mintWeeklyARC();
    }

    require(
      user.lastDnmWithdrawNetworkerWeekNumber < passedWeekNumber,
      "Networker has already calculated DNM for this week."
    );

    uint256 userWeekSteps = 0;

    for (uint8 i = 0; i < 7; i++) {
      uint256 dayNumber = (passedWeekNumber) * 7 + i;
      for (uint8 j = 0; j < 3; j++) {
        userWeekSteps += _getUserDailySteps(userId, dayNumber, j);
      }
    }

    require(totalDnmWeeklySteps > 0, "No steps recorded for the week");

    uint256 networkerDnmShare = (((lastWeekDnmMintAmount * 60) / 100) *
      userWeekSteps) / totalDnmWeeklySteps;

    totalDnmEarned += ((networkerDnmShare * 30) / 100);
    user.networkerDnmShare += ((networkerDnmShare * 30) / 100);

    console.log("totalDnmWeeklySteps: %d", totalDnmWeeklySteps);
    console.log("lastWeekDnmMintAmount: %d", lastWeekDnmMintAmount);
    console.log("userWeekSteps: %d", userWeekSteps);
    console.log("networkerDnmShare: %d", networkerDnmShare);
    console.log("user.networkerDnmShare: %d", user.networkerDnmShare);
    console.log("transferAmount: %d", (networkerDnmShare * 70) / 100);

    user.lastDnmWithdrawNetworkerWeekNumber = passedWeekNumber;

    _transferDnm(msg.sender, (networkerDnmShare * 70) / 100);

    emit CoreLib.NetworkerArcShareCalculated(
      userId,
      passedWeekNumber,
      networkerDnmShare
    );
  }

  function calculateUserWeeklyArc() public nonReentrant {
    uint256 userId = getUserIdByAddress(msg.sender);
    UserLib.User storage user = users[userId];
    uint256 passedWeekNumber = HelpersLib.getWeekOfTs(block.timestamp) - 1;

    if (passedWeekNumber > dnmMintWeekNumber) {
      mintWeeklyARC();
    }

    require(
      user.lastDnmWithdrawUserWeekNumber < passedWeekNumber,
      "User has already calculated ARC for this week."
    );

    require(_getWeeklyBv(passedWeekNumber) > 0, "No BV recorded for the week");

    uint256 userLastWeekBv = _getUserWeeklyBv(userId, passedWeekNumber);
    uint256 totalWeekBv = _getWeeklyBv(passedWeekNumber);

    uint256 userDnmShare = ((lastWeekDnmMintAmount * 35) / 100) *
      (userLastWeekBv / totalWeekBv);

    user.lastDnmWithdrawUserWeekNumber = passedWeekNumber;

    console.log("passedWeekNumber: %d", passedWeekNumber);
    console.log("lastWeekDnmMintAmount: %d", lastWeekDnmMintAmount);
    console.log("userLastWeekBv: %d", userLastWeekBv);
    console.log("totalWeekBv: %d", totalWeekBv);

    _transferDnm(msg.sender, userDnmShare);

    emit CoreLib.UserArcShareCalculated(userId, passedWeekNumber, userDnmShare);
  }

  function calculateSellerWeeklyArc() public nonReentrant {
    uint256 sellerId = getSellerIdByAddress(msg.sender);
    SellerLib.Seller storage seller = _getSellerById(sellerId);
    uint256 passedWeekNumber = HelpersLib.getWeekOfTs(block.timestamp) - 1;

    if (passedWeekNumber > dnmMintWeekNumber) {
      mintWeeklyARC();
    }

    require(
      seller.lastDnmWithdrawWeekNumber < passedWeekNumber,
      "Seller has already calculated ARC for this week."
    );

    require(_getWeeklyBv(passedWeekNumber) > 0, "No BV recorded for the week");

    uint256 sellerDnmShare = (((lastWeekDnmMintAmount * 5) / 100) *
      sellerWeeklyBv[sellerId][passedWeekNumber]) /
      _getWeeklyBv(passedWeekNumber);

    seller.lastDnmWithdrawWeekNumber = passedWeekNumber;

    _transferDnm(msg.sender, sellerDnmShare);


    emit CoreLib.SellerArcShareCalculated(
      sellerId,
      passedWeekNumber,
      sellerDnmShare
    );
  }

  function monthlyWithdrawNetworkerArc() public nonReentrant {
    uint256 userId = getUserIdByAddress(msg.sender);
    UserLib.User storage user = users[userId];

    uint256 userCreationDistance = (HelpersLib.getDistanceInDays(
      user.createdAt,
      block.timestamp
    ) / 90);

    require(
      userCreationDistance > user.withdrawNetworkerDnmShareMonth,
      "User has already withdrawn ARC share for this 3 month period"
    );

    uint256 dnmAmount = (user.networkerDnmShare * 25) / 100;

    user.networkerDnmShare -= dnmAmount;
    user.withdrawNetworkerDnmShareMonth = userCreationDistance;
    totalDnmEarned -= dnmAmount;

    _transferDnm(msg.sender, dnmAmount);

    emit CoreLib.NetworkerMonthlyArcShareWithdrawn(
      userId,
      userCreationDistance,
      dnmAmount
    );
  }

  function setMaxSteps(uint256 steps) public onlyManager {
    _setWeeklyMaxSteps(steps);
  }
}