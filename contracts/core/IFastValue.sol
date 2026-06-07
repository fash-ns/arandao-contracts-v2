// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {UserLib} from "./UserLib.sol";

interface IFastValue {
  function addMonthlyFv(uint256 month, uint256 amount) external;

  function getUserShare(
    uint256 userId,
    uint256 month
  ) external view returns (uint8);

  function checkUserAuthorityForFvEntrance(
    UserLib.User calldata user,
    uint256 userId,
    uint256 minBv,
    uint256 month,
    uint256 orderDate
  )
    external
    returns (
      uint256 fvEntranceMonth,
      uint8 fvEntranceShare,
      uint256 minBvForFv
    );

  function registerUserFvFromPurchase(
    UserLib.User calldata user,
    uint256 userId,
    uint256 month
  ) external;
}
