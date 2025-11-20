// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {IDNM} from "./IDNM.sol";
import {HelpersLib} from "./HelpersLib.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IVault} from "./IVault.sol";

contract Finance {
  event weeklyDnmMinted(uint256 weekNumber, uint256 amount);

  /// @notice Last calculated week ARC mint amount
  uint256 public lastWeekArcMintAmount;

  /// @notice Last ARC mint week number
  uint256 public arcMintWeekNumber;

  /// @dev Total commission earned and not withdrawn.
  uint256 public totalCommissionEarned;

  /// @dev Total ARC earned and not withdrawn.
  uint256 public totalArcEarned;

  /// @dev ARC token address
  address public arcAddress;

  /// @dev Payment token address (Could be DAI for example)
  address public paymentTokenAddress;

  /// @dev Vault contract address
  address public vaultAddress;

  /// @notice Maps week to total BV for that week
  mapping(uint256 => uint256) public totalWeeklyBv;

  function __Finance_init(
    address _paymentTokenAddress,
    address _arcAddress
  ) internal {
    paymentTokenAddress = _paymentTokenAddress;
    arcAddress = _arcAddress;
    lastWeekArcMintAmount = 0;
    arcMintWeekNumber = 0;
    totalCommissionEarned = 0;
    totalArcEarned = 0;
  }

  function _transferPaymentToken(
    address to,
    uint256 value
  ) internal returns (bool) {
    IERC20 paymentToken = IERC20(paymentTokenAddress);

    uint256 balance = paymentToken.balanceOf(address(this));
    if (value > balance) {
      IVault vaultContract = IVault(vaultAddress);
      vaultContract.withdrawDai(value - balance);
    }
    return paymentToken.transfer(to, value);
  }

  function _mintWeeklyDnm() internal {
    uint256 pastWeekNumber = HelpersLib.getWeekOfTs(block.timestamp) - 1;
    require(
      arcMintWeekNumber < pastWeekNumber,
      "DNM of this week is already minted."
    );
    //Total BV - 20% for FV
    uint256 pastWeekTotalBv = totalWeeklyBv[pastWeekNumber];
    uint256 pastWeekBv = (pastWeekTotalBv * 80) / 100;
    require(pastWeekBv >= 100 ether, "This week's BV is less than 100.");

    IVault vaultContract = IVault(vaultAddress);

    uint256 priceFromVault = vaultContract.getPrice();

    IDNM dnmContract = IDNM(arcAddress);
    uint256 currentExcessDnmBalance = dnmContract.balanceOf(address(this)) -
      totalArcEarned;

    //Price = ((Remaining BV) + (DEX stock price)) / TOTAL SUPPLY
    uint256 totalSupply = dnmContract.totalSupply();
    uint256 adjustedSupply = totalSupply - currentExcessDnmBalance;
    require(adjustedSupply > 0, "Adjusted supply cannot be zero");
    uint256 p = ((
      (((pastWeekTotalBv * 397) / 1000) +
        ((priceFromVault * totalSupply)) / 1000000000000000000)
    ) * 1000000000000000000) / adjustedSupply;

    require(p > 0, "Price cannot be zero");
    //mint amount = (.078 * total BV) / Price
    uint256 mintAmount = (((pastWeekTotalBv * 78) / 1000) *
      1000000000000000000) / p;

    // Mintcap = 247 ether
    if (mintAmount > 247 ether) {
      mintAmount = 247 ether;
    }

    if (mintAmount > currentExcessDnmBalance) {
      dnmContract.mint(address(this), mintAmount - currentExcessDnmBalance);
    }

    IERC20 paymentToken = IERC20(paymentTokenAddress);
    uint256 dexTransferAmount = pastWeekBv - totalCommissionEarned;

    // Approve vault to take the amount that core wants to transfer
    paymentToken.approve(vaultAddress, dexTransferAmount);
    // Transfer token to dex
    vaultContract.deposit(dexTransferAmount);
    lastWeekArcMintAmount = mintAmount;
    arcMintWeekNumber = pastWeekNumber;

    emit weeklyDnmMinted(pastWeekNumber, mintAmount);
  }

  function _transferDnm(address to, uint256 amount) internal returns (bool) {
    IDNM dnmToken = IDNM(arcAddress);
    return dnmToken.transfer(to, amount);
  }

  function _addTotalWeekBv(uint256 weekNumber, uint256 amount) internal {
    totalWeeklyBv[weekNumber] += amount;
  }

  function _getWeeklyBv(uint256 weekNumber) internal view returns (uint256) {
    return totalWeeklyBv[weekNumber];
  }
}
