// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {HelpersLib} from "./HelpersLib.sol";

contract CalculationLogic {
  event MaxStepSet(uint256 steps);

  uint256 public weeklyCalculationStartTime;
  uint256 public _maxSteps;
  uint256 public _bvBalance;
  uint256 public _commissionPerStep;
  uint256 public _minBv;

  constructor() {
    _maxSteps = 6;
    _bvBalance = 500 ether;
    _commissionPerStep = 60 ether;
    _minBv = 100 ether;
  }

  function _activateWeeklyCalculation(uint256 timestamp) internal {
    require(
      weeklyCalculationStartTime == 0,
      "Calculation logic is already switched to weekly"
    );

    uint256 weekNumber = HelpersLib.getWeekOfTs(timestamp);
    weeklyCalculationStartTime = HelpersLib.getStartWeekTs(weekNumber + 1);
  }

  function _setWeeklyMaxSteps(uint256 steps) internal {
    require(
      _isWeeklyCalculationActive(),
      "Max steps can only be set when weekly calculation flow is activated."
    );
    require(steps >= 6 && steps <= 40, "Max steps must be between 5 - 40");
    _maxSteps = steps;

    emit MaxStepSet(steps);
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
    if (_isWeeklyCalculationActive() && _bvBalance == 500 ether) {
      _bvBalance = 1000 ether;
    }
    return _bvBalance;
  }

  function _getMinBv() internal returns (uint256) {
    if (_isWeeklyCalculationActive() && _minBv == 100 ether) {
      _minBv = 300 ether;
    }
    return _minBv;
  }

  function _getCommissionPerStep() internal returns (uint256) {
    if (_isWeeklyCalculationActive() && _commissionPerStep == 60 ether) {
      _commissionPerStep = 100 ether;
    }
    return _commissionPerStep;
  }
}
