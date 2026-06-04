// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {FastValueLib} from "./FastValueLib.sol";
import {ICore} from "./ICore.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

contract FastValue is FastValueLib {
  using SafeERC20 for IERC20;

  constructor(
    address _paymentTokenAddress,
    address _coreContractAddress
  ) FastValueLib(_paymentTokenAddress, _coreContractAddress) {}

  function setTotalMonthlyFv(
    uint256[] memory months,
    uint256[] memory totalShares,
    uint256[] memory totalAmounts
  ) external onlyDevMode {
    require(
      months.length == totalShares.length &&
        totalShares.length == totalAmounts.length
    );
    uint256 len = months.length;

    for (uint256 i = 0; i < len; i++) {
      monthlyTotalShares[months[i]] = totalShares[i];
      monthlyFv[months[i]] = totalAmounts[i];
    }
  }

  function setUserMonthlyFv(
    uint256 userId,
    uint256[] memory months,
    uint8[] memory shares,
    bool[] memory isWithdrawn
  ) external onlyDevMode {
    require(
      months.length == shares.length && shares.length == isWithdrawn.length
    );
    uint256 len = months.length;

    for (uint256 i = 0; i < len; i++) {
      monthlyUserShares[months[i]][userId] = shares[i];
      monthlyUserShareWithdraws[months[i]][userId] = isWithdrawn[i];
    }
  }

  function revokeDevMode() external onlyDevMode {
    devMode = false;
  }

  function submitUserForFastValue(
    uint256 userId,
    uint256 month,
    uint8 share
  ) internal {
    if (monthlyUserShares[month][userId] == 0) {
      monthlyUserShares[month][userId] = share;
      monthlyTotalShares[month] += share;

      emit UserAddedToFastValue(userId, month, share);
    }
  }

  function addMonthlyFv(
    uint256 month,
    uint256 amount
  ) external onlyCoreContract {
    IERC20 paymentToken = IERC20(paymentTokenAddress);
    paymentToken.safeTransferFrom(msg.sender, address(this), amount);
    monthlyFv[month] += amount;
  }

  function getUserShareInPaymentToken(
    uint256 userId,
    uint256 month
  ) public view returns (uint256) {
    if (
      monthlyUserShares[month][userId] == 0 ||
      monthlyUserShareWithdraws[month][userId]
    ) {
      return 0;
    }
    return
      (monthlyFv[month] * monthlyUserShares[month][userId]) /
      monthlyTotalShares[month];
  }

  function getUserShare(
    uint256 userId,
    uint256 month
  ) public view returns (uint8) {
    return monthlyUserShares[month][userId];
  }

  function withdrawFastValueShare(uint256 selectedMonth) public nonReentrant {
    ICore coreContract = ICore(coreContractAddress);

    uint256 userId = coreContract.getUserIdByAddress(msg.sender);
    if (userId == 0) {
      revert UserNotFound();
    }
    uint256 pastMonth = coreContract.getCurrentMonthNo() - 1;

    if (selectedMonth > pastMonth) {
      revert CannotWithdrawCurrentMonthShare();
    }

    uint8 userShare = monthlyUserShares[selectedMonth][userId];
    bool isWithdrawn = monthlyUserShareWithdraws[selectedMonth][userId];

    if (userShare == 0) {
      revert UserHasNoFastValueShares();
    }

    if (isWithdrawn) {
      revert UserHasAlreadyWithdrawnFastValueShare();
    }

    uint256 userFvShare = getUserShareInPaymentToken(userId, selectedMonth);

    monthlyUserShareWithdraws[selectedMonth][userId] = true;

    IERC20 paymentToken = IERC20(paymentTokenAddress);
    paymentToken.safeTransfer(msg.sender, userFvShare);

    emit MonthlyFastValueWithdrawn(userId, selectedMonth, userFvShare);
  }

  function checkUserAuthorityForFvEntrance(
    CoreUser memory user,
    uint256 userId,
    uint256 minBv,
    uint256 month,
    uint256 orderDate
  ) external onlyCoreContract returns (CoreUser memory) {
    if (!user.migrated) {
      if (user.createdAt + 30 days > orderDate) {
        submitUserForFastValue(userId, month, 2);
        user.fvEntranceMonth = month;
        user.fvEntranceShare = 2;
        user.minBvForFv = minBv;
      } else if (
        user.createdAt + 60 days > orderDate && (user.bv >= (minBv * 22) / 10) //100% BV for first month + 120% BV for next month
      ) {
        submitUserForFastValue(userId, month, 1);
        user.fvEntranceMonth = month;
        user.fvEntranceShare = 1;
        user.minBvForFv = minBv;
      }
    }
    return user;
  }

  function registerUserFvFromPurchase(
    CoreUser memory user,
    uint256 userId,
    uint256 month
  ) external onlyCoreContract {
    if (!user.migrated) {
      if (
        (user.fvEntranceShare == 2 && user.fvEntranceMonth + 12 > month) ||
        (user.fvEntranceShare == 1 && user.fvEntranceMonth + 11 > month)
      ) {
        uint256 requiredBvForFastValue = user.minBvForFv;
        if (user.fvEntranceShare == 1) {
          requiredBvForFastValue += (user.minBvForFv * 12) / 10;
        }
        uint8 lastMonthIndex = 10 + user.fvEntranceShare; // 11 for one share and 12 for two shares.
        for (uint8 i = 1; i < lastMonthIndex; i++) {
          // In order to prevent user to be added to fast value for a past month.
          if (user.fvEntranceMonth + i < month) {
            continue;
          }

          // If user misses the required BV for previous month, the FV condition will be revoked.
          if (getUserShare(userId, user.fvEntranceMonth + i - 1) == 0) {
            break;
          }

          if (user.fvEntranceShare == 1) {
            requiredBvForFastValue += ((user.minBvForFv * (12 ** (i + 1))) /
              (10 ** (i + 1)));
          } else {
            requiredBvForFastValue += ((user.minBvForFv * (12 ** i)) /
              (10 ** i));
          }
          if (user.bv < requiredBvForFastValue) {
            break;
          }
          submitUserForFastValue(
            userId,
            user.fvEntranceMonth + i,
            user.fvEntranceShare
          );
        }
      }
    }
  }
}
