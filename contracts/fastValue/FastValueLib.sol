// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

abstract contract FastValueLib is Ownable, ReentrancyGuard {
  event UserAddedToFastValue(uint256 userId, uint256 month, uint8 share);
  event MonthlyFastValueWithdrawn(uint256 userId, uint256 month, uint256 share);

  error UnAuthorizedCoreContract();
  error NotInDevMode();
  error UnAuthorizedOwner();
  error UserHasNoFastValueShares();
  error UserHasAlreadyWithdrawnFastValueShare();
  error CannotWithdrawCurrentMonthShare();

  mapping(uint256 => mapping(uint256 => uint8)) public monthlyUserShares; //month to user ID to user share. share can be 0 - 2
  mapping(uint256 => mapping(uint256 => bool)) public monthlyUserShareWithdraws; //month to user ID to a boolean which shows if the user is withdrawn his share.
  mapping(uint256 => uint256) public monthlyTotalShares; //month to total share count
  mapping(uint256 => uint256) public monthlyFv; //month to total fast value;

  address public coreContractAddress;
  address public paymentTokenAddress;
  bool public devMode;

  constructor(address _paymentTokenAddress) Ownable(msg.sender) {
    paymentTokenAddress = _paymentTokenAddress;
  }

  modifier onlyCoreContract() {
    if (msg.sender != coreContractAddress) {
      revert UnAuthorizedCoreContract();
    }
    _;
  }

  modifier onlyDevMode() {
    if (!devMode) {
      revert NotInDevMode();
    }
    if (msg.sender != owner()) {
      revert UnAuthorizedOwner();
    }
    _;
  }
}
