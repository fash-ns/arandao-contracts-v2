// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {IDNM} from "./IDNM.sol";
import {HelpersLib} from "./HelpersLib.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

contract Finance {
  /// @notice Last calculated week DNM mint amount
  uint256 lastWeekDnmMintAmount = 0;

  /// @notice Last DNM mint week number
  uint256 dnmMintWeekNumber = 0;

  /// @dev Total commission earned and not withdrawn.
  uint256 public totalCommissionEarned = 0;

  /// @dev Total dnm earned and not withdrawn.
  uint256 public totalDnmEarned = 0;

  /// @dev DNM token address
  address public dnmAddress;

  /// @dev Payment token address (Could be DAI for example)
  address public paymentTokenAddress;

  /// @dev Vault contract address
  address public vaultAddress;

  /// @notice Maps week to total BV for that week
  mapping(uint256 => uint256) public totalWeeklyBv;

  constructor(
    address _paymentTokenAddress,
    address _dnmAddress,
    address _vaultAddress
  ) {
    paymentTokenAddress = _paymentTokenAddress;
    dnmAddress = _dnmAddress;
    vaultAddress = _vaultAddress;
  }

  function _transferPaymentToken(
    address to,
    uint256 value
  ) internal returns (bool) {
    IERC20 paymentToken = IERC20(paymentTokenAddress);

    uint256 balance = paymentToken.balanceOf(address(this));
    if (value > balance) {
      //TODO: Ask dex to convert tokens and transfers those to the contract.
    }
    return paymentToken.transferFrom(address(this), to, value);
  }

  function _mintWeeklyDnm() internal {
    uint256 pastWeekNumber = HelpersLib.getWeekOfTs(block.timestamp) - 1;
    require(
      dnmMintWeekNumber < pastWeekNumber,
      "DNM of this week is already minted."
    );
    //Total BV - 20% for FV
    uint256 pastWeekBv = (totalWeeklyBv[pastWeekNumber] * 80) / 100;
    require(pastWeekBv >= 100 ether, "This week's BV is less than 100.");

    uint256 priceFromDex = 1; //TODO: get the price from DEX

    IDNM dnmContract = IDNM(dnmAddress);
    uint256 currentExcessDnmBalance = dnmContract.balanceOf(address(this)) -
      totalDnmEarned;

    //Price = ((Remaining BV) + (DEX stock price)) / TOTAL SUPPLY
    uint256 p = (pastWeekBv + priceFromDex - totalCommissionEarned) /
      (dnmContract.totalSupply() - currentExcessDnmBalance);

    //mint amount = (.078 * total BV) / Price
    uint256 mintAmount = ((pastWeekBv * 78) / 1000) / p;

    dnmContract.mint(address(this), mintAmount - currentExcessDnmBalance);

    IERC20 paymentToken = IERC20(paymentTokenAddress);
    uint256 dexTransferAmount = paymentToken.balanceOf(address(this)) -
      totalCommissionEarned;

    //TODO: Transfer (all DAI balance - totalCommissionEarned) to DEX.

    lastWeekDnmMintAmount = mintAmount;
    dnmMintWeekNumber = pastWeekNumber;
  }

  function _transferDnm(address to, uint256 amount) internal returns (bool) {
    IDNM dnmToken = IDNM(dnmAddress);
    return dnmToken.transferFrom(address(this), to, amount);
  }

  function _addTotalWeekBv(uint256 weekNumber, uint256 amount) internal {
    totalWeeklyBv[weekNumber] += amount;
  }

  function _getWeeklyBv(uint256 weekNumber) internal view returns (uint256) {
    return totalWeeklyBv[weekNumber];
  }
}
