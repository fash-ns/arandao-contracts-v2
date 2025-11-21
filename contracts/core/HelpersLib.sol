// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {BokkyPooBahsDateTimeLibrary} from "./BokkyPooBahsDateTimeLibrary.sol";

library HelpersLib {
  // Mon 10 Nov 2025
  uint256 constant offset = 1762732800;

  /**
   * @notice Gets the current day number from offset (timestamp / 86400)
   * @return The current day number
   */
  function getDayOfTs(uint256 timestamp) internal pure returns (uint256) {
    if (timestamp <= offset) return 0;
    return (timestamp - offset) / 86400;
  }

  /**
   * @notice Gets the current week number from offset
   * @return The current week number
   */
  function getWeekOfTs(uint256 timestamp) internal pure returns (uint256) {
    return getDayOfTs(timestamp) / 7;
  }

  function getStartWeekTs(uint256 weekNumber) internal pure returns (uint256) {
    return (weekNumber * 7 * 20) + offset;
  }

  function getMonth(uint256 timestamp) internal pure returns (uint256) {
    (uint year, uint month, ) = BokkyPooBahsDateTimeLibrary.timestampToDate(
      timestamp
    );

    return ((year - 2025) * 12 + month);
  }

  function _isFirstDayOfWeek(uint256 timestamp) internal pure returns (bool) {
    return
      HelpersLib.getWeekOfTs(timestamp) * 7 == HelpersLib.getDayOfTs(timestamp);
  }

  function getDistanceInDays(
    uint256 tsA,
    uint256 tsB
  ) internal pure returns (uint256) {
    return (tsB - tsA) / 86400;
  }
}
