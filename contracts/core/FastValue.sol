// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {HelpersLib} from "./HelpersLib.sol";

contract FastValue {
    event UserAddedToFastValue(uint256 userId, uint256 month, uint8 share);

    mapping(uint256 => mapping(uint256 => uint8)) public monthlyUserShares; //month to user ID to user share. share can be 0 - 2
    mapping(uint256 => mapping(uint256 => bool))
        public monthlyUserShareWithdraws; //month to user ID to a boolean which shows if the user is withdrawn his share.
    mapping(uint256 => uint256) public monthlyTotalShares; //month to total share count
    mapping(uint256 => uint256) public monthlyFv; //month to total fast value;

    function _submitUserForFastValue(
        uint256 userId,
        uint256 month,
        uint8 share
    ) internal {
        if (monthlyUserShares[month][userId] == 0) {
            monthlyUserShares[month][userId] = share;
            monthlyTotalShares[month] += share;

            emit UserAddedToFastValue(userId, month, share);
        }
    }

    function _addMonthlyFv(uint256 amount) internal {
        uint256 month = HelpersLib.getMonth(block.timestamp);
        monthlyFv[month] += amount;
    }

    function _getUserShare(
        uint256 userId,
        uint256 month
    ) internal view returns (uint256) {
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
}
