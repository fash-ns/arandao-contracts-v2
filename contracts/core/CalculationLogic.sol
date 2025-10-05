// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {HelpersLib} from "./HelpersLib.sol";

contract CalculationLogic {
  event MaxStepSet(uint256 steps);

  uint256 weeklyCalculationStartTime;
  uint256 maxSteps = 5;
  uint256 bvBalance = 500 ether;
  uint256 commissionPerStep = 60 ether;
  uint256 minBv = 100 ether;

  function _activateWeeklyCalculateion(uint256 timestamp) internal {
    require(
      weeklyCalculationStartTime == 0,
      "Calculation logic is already switched to weekly"
    );

    uint256 weekNumber = HelpersLib.getWeekOfTs(timestamp);
    weeklyCalculationStartTime = HelpersLib.getStartWeekTs(weekNumber + 1);
    maxSteps = 20;
    bvBalance = 600 ether;
    minBv = 200;
    commissionPerStep = 70 ether;
  }

  function _setWeeklyMaxSteps(uint256 steps) internal {
    require(steps >= 5 && steps <= 20, "Max steps must be between 5 - 20");
    maxSteps = steps;

    emit MaxStepSet(steps);
  }
}
