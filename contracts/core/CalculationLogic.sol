// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {HelpersLib} from "./HelpersLib.sol";

contract CalculationLogic {
  event MaxStepSet(uint256 steps);
  event WeeklyCalculationActivated(uint256 startTime);

  uint256 public weeklyCalculationStartTime;
  uint256 public _maxSteps;
  uint256 public _bvBalance;
  uint256 public _commissionPerStep;
  uint256 public _minBv;
  uint256 public _paymentTokenDecimals;

  constructor() {
    _maxSteps = 6;
    _paymentTokenDecimals = 1000000;
    _bvBalance = 500 * _paymentTokenDecimals;
    _commissionPerStep = 60 * _paymentTokenDecimals;
    _minBv = 100 * _paymentTokenDecimals;
  }

  function _activateWeeklyCalculation(uint256 timestamp) internal {
    require(
      weeklyCalculationStartTime == 0,
      "Calculation logic is already switched to weekly"
    );

    uint256 weekNumber = HelpersLib.getWeekOfTs(timestamp);
    weeklyCalculationStartTime = HelpersLib.getStartWeekTs(weekNumber + 1);
    emit WeeklyCalculationActivated(weeklyCalculationStartTime);
  }

  function _reduceMaxSteps() internal {
    if (_maxSteps > 7) {
      _maxSteps -= 1;
      emit MaxStepSet(_maxSteps);
    }
  }

  function _isWeeklyCalculationActive() internal view returns (bool) {
    return (weeklyCalculationStartTime > 0 &&
      weeklyCalculationStartTime < block.timestamp);
  }

  function _getMaxSteps() internal returns (uint256) {
    if (_isWeeklyCalculationActive() && _maxSteps == 6) {
      _maxSteps = 50;
    }
    return _maxSteps;
  }

  function _getBvBalance() internal returns (uint256) {
    if (
      _isWeeklyCalculationActive() && _bvBalance == 500 * _paymentTokenDecimals
    ) {
      _bvBalance = 1000 * _paymentTokenDecimals;
    }
    return _bvBalance;
  }

  function _getMinBv() internal returns (uint256) {
    if (_isWeeklyCalculationActive() && _minBv == 100 * _paymentTokenDecimals) {
      _minBv = 300 * _paymentTokenDecimals;
    }
    return _minBv;
  }

  function _getCommissionPerStep() internal returns (uint256) {
    if (
      _isWeeklyCalculationActive() &&
      _commissionPerStep == 60 * _paymentTokenDecimals
    ) {
      _commissionPerStep = 100 * _paymentTokenDecimals;
    }
    return _commissionPerStep;
  }
}
