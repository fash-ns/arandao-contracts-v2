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

  constructor(
    address _paymentTokenAddress,
    address _coreContractAddress
  ) Ownable(msg.sender) {
    paymentTokenAddress = _paymentTokenAddress;
    coreContractAddress = _coreContractAddress;
    devMode = true;
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

  struct CoreUser {
    uint256 parentId; // Parent user ID (0 for root)
    address userAddress; // Address of the user
    uint8 position; // Position under parent (0-3)
    bytes32[] path; // Encoded path from root to user
    uint256 lastCalculatedOrder; // Last processed order ID for this user
    uint256[4] childrenBv; // Accumulated BV for each direct childs of normal nodes position
    uint256[4] childrenAggregateBv; // Accumulated BV for each direct childs of normal nodes position. Aggregated
    uint256[2] normalNodesBv; // Accumulated BV for normal nodes
    uint256 bv; // User's total business volume
    uint256 eligibleArcWithdrawWeekNo; // Week number when user could withdraw earned ARC (networker side)
    uint256 superNodeTotalSteps; // User's total steps
    uint256 bvOnBridgeTime; // User's bv when the user is bridged
    uint256 fvEntranceMonth; // The month number where user entered fast value pool
    uint8 fvEntranceShare; // Could be 1 for half share and 2 for whole share
    uint256 minBvForFv; // The minimum BV for user to enter fast value pool
    bool migrated; //True for users who are bridged from old smart contract
    uint256 withdrawableCommission; // User's earned commission available for withdrawal
    uint256 lastArcWithdrawNetworkerWeekNumber; // User's last week number of ARC withdraw for networker
    uint256 lastArcWithdrawUserWeekNumber; // User's last week number of ARC withdraw for user
    uint256 createdAt; // Block timestamp of registration
    bool active; // Whether user is active
  }
}
