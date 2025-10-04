// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {BokkyPooBahsDateTimeLibrary} from "./BokkyPooBahsDateTimeLibrary.sol";

library HelpersLib {
  // Mon 29 Sep 2025
  uint256 constant offset = 1759091400;

  /**
   * @notice Gets the current day number from 29 Sep 2025 (timestamp / 86400)
   * @return The current day number
   */
  function getDayOfTs(uint256 timestamp) internal pure returns (uint256) {
    return (timestamp - offset) / 86400;
  }

  /**
   * @notice Gets the current week number from 29 Sep 2025
   * @return The current week number
   */
  function getWeekOfTs(uint256 timestamp) internal pure returns (uint256) {
    return getDayOfTs(timestamp) / 7;
  }

  function getStartWeekTs(uint256 weekNumber) internal pure returns (uint256) {
    return (weekNumber * 7 * 86400) + offset;
  }

  function getMonth(uint256 timestamp) internal pure returns (uint256) {
    (uint year, uint month, ) = BokkyPooBahsDateTimeLibrary.timestampToDate(
      timestamp
    );

    return ((year - 2025) * 12 + month);
  }
}
