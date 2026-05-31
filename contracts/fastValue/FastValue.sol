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
    uint256 month,
    uint256 totalShares,
    uint256 totalAmount
  ) external onlyDevMode {
    monthlyTotalShares[month] = totalShares;
    monthlyFv[month] = totalAmount;
  }

  function setUserMonthlyFv(
    uint256 month,
    uint256 userId,
    uint8 share,
    bool isWithdrawn
  ) external onlyDevMode {
    monthlyUserShares[month][userId] = share;
    monthlyUserShareWithdraws[month][userId] = isWithdrawn;
  }

  function revokeDevMode() external onlyDevMode {
    devMode = false;
  }

  function submitUserForFastValue(
    uint256 userId,
    uint256 month,
    uint8 share
  ) external onlyCoreContract {
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
}
