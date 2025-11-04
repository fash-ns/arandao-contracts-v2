// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {HelpersLib} from "./HelpersLib.sol";

contract CalculationLogic {
  event MaxStepSet(uint256 steps);

  //TODO: Change to private
  uint256 public weeklyCalculationStartTime;
  uint256 public _maxSteps = 5;
  uint256 public _bvBalance = 5 ether; //TODO: Change to 500 ether
  uint256 public _commissionPerStep = 600000000000000000; //TODO: Change to 60 ether
  uint256 public _minBv = 1 ether; //TODO: CHange to 100 ether

  function _activateWeeklyCalculation(uint256 timestamp) internal {
    require(
      weeklyCalculationStartTime == 0,
      "Calculation logic is already switched to weekly"
    );

    uint256 weekNumber = HelpersLib.getWeekOfTs(timestamp);
    weeklyCalculationStartTime = HelpersLib.getStartWeekTs(weekNumber + 1);
  }

  function _setWeeklyMaxSteps(uint256 steps) internal {
    require(_isWeeklyCalculationActive(), "Max steps can only be set when weekly calculation flow is activated.");
    require(steps >= 5 && steps <= 40, "Max steps must be between 5 - 40");
    _maxSteps = steps;

    emit MaxStepSet(steps);
  }

  function _isWeeklyCalculationActive() internal view returns (bool) {
    return (weeklyCalculationStartTime > 0 &&
      weeklyCalculationStartTime < block.timestamp);
  }

  function _getMaxSteps() internal returns (uint256) {
    if (_isWeeklyCalculationActive() && _maxSteps == 5) {
      _maxSteps = 40;
    }
    return _maxSteps;
  }

  function _getBvBalance() internal returns (uint256) {
    if (_isWeeklyCalculationActive() && _bvBalance == 5 ether) { //TODO: Change to 500 and 600
      _bvBalance = 6 ether;
    }
    return _bvBalance;
  }

  function _getMinBv() internal returns (uint256) {
    if (_isWeeklyCalculationActive() && _minBv == 1 ether) { //TODO: Change to 100 and 200
      _minBv = 2 ether;
    }
    return _minBv;
  }

  function _getCommissionPerStep() internal returns (uint256) {
    if (_isWeeklyCalculationActive() && _commissionPerStep == 600000000000000000) { //TODO: Change to 60 and 70
      _commissionPerStep = 700000000000000000;
    }
    return _commissionPerStep;
  }
}
