// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {HelpersLib} from "./HelpersLib.sol";

contract CalculationLogic {
    event MaxStepSet(uint256 steps);

    uint256 public weeklyCalculationStartTime;
    uint256 public _maxSteps = 5;
    uint256 public _bvBalance = 500 ether;
    uint256 public _commissionPerStep = 60 ether;
    uint256 public _minBv = 100 ether;

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
        if (_isWeeklyCalculationActive() && _bvBalance == 500 ether) {
            _bvBalance = 600 ether;
        }
        return _bvBalance;
    }

    function _getMinBv() internal returns (uint256) {
        if (_isWeeklyCalculationActive() && _minBv == 100 ether) {
            _minBv = 200 ether;
        }
        return _minBv;
    }

    function _getCommissionPerStep() internal returns (uint256) {
        if (_isWeeklyCalculationActive() && _commissionPerStep == 60 ether) {
            _commissionPerStep = 70 ether;
        }
        return _commissionPerStep;
    }
}
