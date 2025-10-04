// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {HelpersLib} from "./HelpersLib.sol";

contract CalculationLogic {
  uint256 weeklyCalculationStartTime;
  uint256 maxSteps = 5;
  uint256 bvBalance = 500 ether;
  uint256 commissionPerStep = 60 ether;

  function _activateWeeklyCalculateion(uint256 timestamp) internal {
    require(
      weeklyCalculationStartTime == 0,
      "Calculation logic is already switched to weekly"
    );

    uint256 weekNumber = HelpersLib.getWeekOfTs(timestamp);
    weeklyCalculationStartTime = HelpersLib.getStartWeekTs(weekNumber + 1);
    maxSteps = 20;
    bvBalance = 600 ether;
    commissionPerStep = 70 ether;
  }

  function _setWeeklyMaxSteps(uint256 steps) internal {
    maxSteps = steps;
  }
}
