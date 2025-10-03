// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {HelpersLib} from "./HelpersLib.sol";

contract FastValue {
  event UserAddedToFastValue(uint256 userId);
  error UserAlreadyHasShare();

  address coreAddress;
  address paymentTokenAddress;
  mapping(uint256 => mapping(uint256 => uint8)) monthlyUserShares; //month to user ID to user share. share can be 0 - 2
  mapping(uint256 => uint256) monthlyTotalShares; //month to total share count

  function _submitUser(uint256 userId, uint8 share) internal {
    uint256 month = HelpersLib.getMonth(block.timestamp);
    if (monthlyUserShares[month][userId] != 0) {
      revert UserAlreadyHasShare();
    }

    monthlyUserShares[month][userId] = share;
    monthlyTotalShares[month] += share;
  }
}
