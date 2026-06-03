// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {Users} from "./Users.sol";
import {Sellers} from "./Sellers.sol";
import {SellerLib} from "./SellerLib.sol";
import {Orders} from "./Orders.sol";
import {OrderLib} from "./OrderLib.sol";
import {UserLib} from "./UserLib.sol";
import {HelpersLib} from "./HelpersLib.sol";
import {Finance} from "./Finance.sol";
import {CalculationLogic} from "./CalculationLogic.sol";
import {CoreLib} from "./CoreLib.sol";
import {SecurityGuard} from "./SecurityGuard.sol";
import {IFastValue} from "./IFastValue.sol";

/**
 * @title DNMCore - Multi-Level Marketing Binary Tree Contract
 * @author Developer: Farbod Shams <farbodshams.2000@gmail.com>
 * DNM is not just a decentralized network marketing platform.
 * It marks a new era in the world of network marketing. Let’s join together!
 * website: https://dnm.pro
 * @notice Implements a secure, gas-conscious MLM tree structure with on-chain order bookkeeping
 */
contract DNMCore is
  ReentrancyGuard,
  Users,
  Sellers,
  Orders,
  Finance,
  CalculationLogic,
  SecurityGuard
{
  /// @notice Amount data structure containing both SV and BV values
  struct Amount {
    address sellerAddress;
    uint256 sv; // Sales Volume
    uint256 bv; // Business Volume
  }

  address feeReceiver;
  address fvAddress;
  bool feeReceiverFlag;

  uint256 totalArcWeeklySteps;

  constructor(
    address initialOwner,
    address _feeReceiver,
    address _arcAddress,
    address _paymentTokenAddress
  )
    Finance(_paymentTokenAddress, _arcAddress)
    SecurityGuard(initialOwner, msg.sender)
  {
    feeReceiver = _feeReceiver;
  }

  function changeFeeReceiverAddress(address newAddr) public onlyOwner {
    if (feeReceiverFlag == false) {
      feeReceiver = newAddr;
      feeReceiverFlag = true;
    } else {
      revert("Fee receiver has already been transferred");
    }
  }

  function setAddresses(
    address _priceFeedAddr,
    address _yieldPoolAddr,
    address _fastValueAddress
  ) public onlyDevMode {
    twapAddress = _priceFeedAddr;
    yieldPoolAddress = _yieldPoolAddr;
    fvAddress = _fastValueAddress;
  }

  /**
   * @notice Migrates old users from old structure.
   * @param data An array of User struct
   */
  function migrateUser(UserLib.User[] calldata data) external onlyDevMode {
    uint256 len = data.length;

    for (uint256 i = 0; i < len; i++) {
      users[nextUserId] = data[i];
      addressToUserId[data[i].userAddress] = nextUserId;
      emit UserLib.UserMigrated(
        nextUserId,
        data[i].parentId,
        data[i].position,
        data[i].userAddress
      );
      nextUserId += 1;
    }
  }

  function mintArc(address[] calldata to, uint256[] calldata amounts) public onlyDevMode {
    require(to.length == amounts.length);
    uint256 len = amounts.length;
    for (uint256 i = 0; i < len; i++) {
      _mintArc(to[i], amounts[i]);
    }
  }

  function revokeDevMode() external onlyDevMode {
    devMode = false;
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
  ) external onlyOrderCreatorContracts(msg.sender) nonReentrant {
    _createOrderFromCore(
      buyerAddress,
      parentAddress,
      position,
      amounts,
      totalAmount
    );
  }

  function _createOrderFromCore(
    address buyerAddress,
    address parentAddress,
    uint8 position,
    Amount[] calldata amounts,
    uint256 totalAmount
  ) internal {
    require(amounts.length > 0, "At least one amount required");

    bool isUserExisted = _userExistsByAddress(buyerAddress);

    uint256 _totalBv = 0;
    for (uint256 i = 0; i < amounts.length; i++) {
      _totalBv += amounts[i].bv;
    }
    require(
      totalAmount >= _totalBv,
      "Provided amount is less than order business amounts"
    );

    _transferPaymentTokenFrom(msg.sender, address(this), totalAmount);
    if (totalAmount - _totalBv > 0) {
      _transferPaymentToken(feeReceiver, totalAmount - _totalBv);
    }
    uint256 minBv = _getMinBv();

    // If new user, validate minimum BV requirement
    if (!isUserExisted) {
      if (_totalBv < minBv) revert CoreLib.InsufficientBVForNewUser();
    }
    uint256 buyerId = _getOrCreateUser(
      buyerAddress,
      parentAddress,
      position,
      lastOrderId,
      minBv
    );
    uint256 weekNumber = HelpersLib.getWeekOfTs(block.timestamp);
    // Process each amount and create orders
    for (uint256 i = 0; i < amounts.length; i++) {
      _createOrderLoop(amounts[i], buyerId, weekNumber);
    }
    _addUserBv(buyerId, weekNumber, _totalBv);
    _addTotalWeekBv(weekNumber, _totalBv);
    IFastValue fvContract = IFastValue(fvAddress);
    uint256 fvTransferAmount = (_totalBv * 20) / 100; // FV = 20% * BV;
    _approvePaymentToken(fvAddress, fvTransferAmount);
    fvContract.addMonthlyFv(getCurrentMonthNo(), fvTransferAmount);
    UserLib.User storage user = _getUserById(buyerId);
    uint256 month = HelpersLib.getMonth(block.timestamp);

    //Add user to fast value if conditions are passed.
    fvContract.registerUserFvFromPurchase(user, buyerId, month);
  }

  function _createOrderLoop(
    Amount calldata amount,
    uint256 buyerId,
    uint256 weekNumber
  ) internal {
    uint256 sellerId = _getOrCreateSeller(amount.sellerAddress);

    _createOrder(buyerId, sellerId, amount.sv, amount.bv);
    _addSellerBv(sellerId, weekNumber, amount.bv);
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

    uint256 lastOrderId = user.lastCalculatedOrder;

    for (uint8 i = 0; i < orderIdsLen; i++) {
      require(
        orderIds[i] > lastOrderId,
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
          lastCalculatedOrderDate > 0 &&
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
          lastCalculatedOrderDate > 0 &&
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
      lastOrderId = orderIds[i];
    }

    if (orderIdsLen > 0) {
      user.lastCalculatedOrder = orderIds[orderIdsLen - 1];

      if (
        weeklyCalculationStartTime > 0 &&
        weeklyCalculationStartTime < block.timestamp
      ) {
        calculateWeeklyCommission(callerId, lastCalculatedOrderDate);
      } else {
        calculateDailyCommission(callerId, lastCalculatedOrderDate);
      }
    }

    if (HelpersLib._isFirstDayOfWeek(block.timestamp)) {
      user.eligibleArcWithdrawWeekNo =
        HelpersLib.getWeekOfTs(block.timestamp) - 1;
    }

    if (orderIdsLen > 0) {
      emit CoreLib.OrdersCalculated(
        callerId,
        orderIdsLen,
        orderIds[orderIdsLen - 1]
      );
    }
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
          if (globalDailyFlushOuts[periodDayNumber] >= 72) {
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
      IFastValue fv = IFastValue(fvAddress);
      uint256 month = HelpersLib.getMonth(lastOrderTimestamp);
      users[userId] = fv.checkUserAuthorityForFvEntrance(
        user,
        userId,
        _getMinBv(),
        month,
        lastOrderTimestamp
      );
    }

    totalCommissionEarned += totalUserCommissionEarned;
    user.withdrawableCommission += totalUserCommissionEarned;
    totalCommissionEarnedByWeek[HelpersLib.getWeekOfTs(lastOrderTimestamp)] +=
      totalUserCommissionEarned;
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

    if (totalCommissionEarned > amount) {
      totalCommissionEarned -= amount;
    } else {
      totalCommissionEarned = 0;
    }

    uint256 contractBalance = _getPaymentTokenBalance(address(this));

    require(
      contractBalance >= amount,
      "Insufficient balance in core. You can withdraw your commission after a purchase in system."
    );

    _transferPaymentToken(msg.sender, amount);

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

    totalArcWeeklySteps = totalWeekSteps;

    uint256 totalCommissionEarnedForWeek = totalCommissionEarnedByWeek[
      passedWeekNumber
    ];
    uint256 totalBvForWeek = (totalWeeklyBv[passedWeekNumber] * 80) / 100; //Total BV - 20% for FV

    if (
      totalCommissionEarnedForWeek >
        totalBvForWeek + (100 * _paymentTokenDecimals) &&
      _isWeeklyCalculationActive()
    ) {
      _reduceMaxSteps();
    }

    _mintWeeklyArc();
  }

  function calculateNetworkerWeeklyARC() public nonReentrant {
    uint256 userId = getUserIdByAddress(msg.sender);
    UserLib.User storage user = users[userId];
    uint256 passedWeekNumber = HelpersLib.getWeekOfTs(block.timestamp) - 1;

    require(
      !HelpersLib._isFirstDayOfWeek(block.timestamp),
      "ARC calculation is not possible at the first day of week."
    );
    require(
      user.eligibleArcWithdrawWeekNo == passedWeekNumber,
      "User hasn't calculated orders at the first day of the week."
    );

    if (passedWeekNumber > arcMintWeekNumber) {
      mintWeeklyARC();
    }

    require(
      user.lastArcWithdrawNetworkerWeekNumber < passedWeekNumber,
      "Networker has already calculated ARC for this week."
    );

    uint256 userWeekSteps = 0;

    for (uint8 i = 0; i < 7; i++) {
      uint256 dayNumber = (passedWeekNumber) * 7 + i;
      for (uint8 j = 0; j < 3; j++) {
        userWeekSteps += _getUserDailySteps(userId, dayNumber, j);
      }
    }

    require(totalArcWeeklySteps > 0, "No steps recorded for the week");

    uint256 networkerArcShare =
      (((lastWeekArcMintAmount * 50) / 100) * userWeekSteps) /
        totalArcWeeklySteps;

    user.lastArcWithdrawNetworkerWeekNumber = passedWeekNumber;

    _transferArc(msg.sender, networkerArcShare);

    emit CoreLib.NetworkerArcShareCalculated(
      userId,
      passedWeekNumber,
      networkerArcShare
    );
  }

  function calculateUserWeeklyArc() public nonReentrant {
    uint256 userId = getUserIdByAddress(msg.sender);
    UserLib.User storage user = users[userId];
    uint256 passedWeekNumber = HelpersLib.getWeekOfTs(block.timestamp) - 1;

    if (passedWeekNumber > arcMintWeekNumber) {
      mintWeeklyARC();
    }

    require(
      user.lastArcWithdrawUserWeekNumber < passedWeekNumber,
      "User has already calculated ARC for this week."
    );

    require(_getWeeklyBv(passedWeekNumber) > 0, "No BV recorded for the week");

    uint256 userLastWeekBv = _getUserWeeklyBv(userId, passedWeekNumber);
    uint256 totalWeekBv = _getWeeklyBv(passedWeekNumber);

    uint256 userArcShare =
      (((lastWeekArcMintAmount * 40) / 100) * userLastWeekBv) / totalWeekBv;

    user.lastArcWithdrawUserWeekNumber = passedWeekNumber;

    _transferArc(msg.sender, userArcShare);

    emit CoreLib.UserArcShareCalculated(userId, passedWeekNumber, userArcShare);
  }

  function calculateSellerWeeklyArc() public nonReentrant {
    uint256 sellerId = getSellerIdByAddress(msg.sender);
    SellerLib.Seller storage seller = _getSellerById(sellerId);
    uint256 passedWeekNumber = HelpersLib.getWeekOfTs(block.timestamp) - 1;

    if (passedWeekNumber > arcMintWeekNumber) {
      mintWeeklyARC();
    }

    require(
      seller.lastArcWithdrawWeekNumber < passedWeekNumber,
      "Seller has already calculated ARC for this week."
    );

    require(_getWeeklyBv(passedWeekNumber) > 0, "No BV recorded for the week");

    uint256 sellerArcShare =
      (((lastWeekArcMintAmount * 10) / 100) *
        sellerWeeklyBv[sellerId][passedWeekNumber]) /
        _getWeeklyBv(passedWeekNumber);

    seller.lastArcWithdrawWeekNumber = passedWeekNumber;

    _transferArc(msg.sender, sellerArcShare);

    emit CoreLib.SellerArcShareCalculated(
      sellerId,
      passedWeekNumber,
      sellerArcShare
    );
  }

  function getCurrentMonthNo() public view returns (uint256) {
    return HelpersLib.getMonth(block.timestamp);
  }

  function addManager(address addr) public onlyOwnerAndDeployerInDevMode {
    _addManager(addr);
  }

  function revokeManager(address addr) public onlyOwnerAndDeployerInDevMode {
    _revokeManager(addr);
  }

  function addWhiteListContract(
    address addr
  ) public onlyOwnerAndDeployerInDevMode {
    _addWhiteListedContract(addr);
  }

  function requestChangeAddress(address newAddress) public {
    _requestChangeAddress(newAddress);
  }

  function cancelChangeAddressRequest() public {
    _cancelChangeAddressRequest();
  }

  function approveChangeAddress(uint256 userId) public {
    _approveChangeAddress(userId);
  }
}
