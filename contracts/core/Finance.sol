// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {IDNM} from "./IDNM.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {HelpersLib} from "./HelpersLib.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IVault} from "./IVault.sol";

contract Finance {
  using SafeERC20 for IDNM;
  using SafeERC20 for IERC20;

  event weeklyArcMinted(uint256 weekNumber, uint256 amount);

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

  constructor(address _paymentTokenAddress, address _arcAddress) {
    paymentTokenAddress = _paymentTokenAddress;
    arcAddress = _arcAddress;
    lastWeekArcMintAmount = 0;
    arcMintWeekNumber = 0;
    totalCommissionEarned = 0;
    totalArcEarned = 0;
  }

  function calculateArcMintAmount(
    uint256 weekNo
  ) public view returns (uint256 mintAmount) {
    uint256 pastWeekTotalBv = totalWeeklyBv[weekNo];

    IVault vaultContract = IVault(vaultAddress);
    uint256 priceFromVault = vaultContract.getPrice();

    IDNM dnmContract = IDNM(arcAddress);
    uint256 currentExcessDnmBalance =
      dnmContract.balanceOf(address(this)) - totalArcEarned;
    uint256 totalSupply = dnmContract.totalSupply();
    uint256 adjustedSupply = totalSupply - currentExcessDnmBalance;
    require(adjustedSupply > 0, "Adjusted supply cannot be zero");

    //Price = ((Remaining BV) + (DEX stock price)) / TOTAL SUPPLY
    uint256 p =
      ((
        (((pastWeekTotalBv * 397) / 1000) +
          ((priceFromVault * totalSupply)) / 1000000000000000000)
      ) * 1000000000000000000) / adjustedSupply;

    require(p > 0, "Price cannot be zero");
    //mint amount = (.078 * total BV) / Price
    mintAmount = (((pastWeekTotalBv * 156) / 1000) * 1000000000000000000) / p;

    // TODO: Remove
    // // Mintcap = 247 ether
    // if (mintAmount > 247 ether) {
    //   mintAmount = 247 ether;
    // }
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

    IDNM dnmContract = IDNM(arcAddress);
    uint256 currentExcessDnmBalance =
      dnmContract.balanceOf(address(this)) - totalArcEarned;

    uint256 mintAmount = calculateArcMintAmount(pastWeekNumber);

    if (mintAmount > currentExcessDnmBalance) {
      _mintArc(address(this), mintAmount - currentExcessDnmBalance);
    }

    IERC20 paymentToken = IERC20(paymentTokenAddress);
    uint256 dexTransferAmount = pastWeekBv - totalCommissionEarned;

    uint256 paymentTokenBalance = paymentToken.balanceOf(address(this));
    if (paymentTokenBalance < dexTransferAmount) {
      dexTransferAmount = paymentTokenBalance;
    }

    if (dexTransferAmount > 0) {
      // Approve vault to take the amount that core wants to transfer
      paymentToken.approve(vaultAddress, dexTransferAmount);
      // Transfer token to dex
      vaultContract.deposit(dexTransferAmount);
    }

    lastWeekArcMintAmount = mintAmount;
    arcMintWeekNumber = pastWeekNumber;

    emit weeklyArcMinted(pastWeekNumber, mintAmount);
  }

  function _mintArc(address to, uint256 amount) internal {
    IDNM dnmContract = IDNM(arcAddress);
    dnmContract.mint(to, amount);
  }

  function _transferArc(address to, uint256 amount) internal {
    IDNM dnmToken = IDNM(arcAddress);
    dnmToken.safeTransfer(to, amount);
  }

  function _transferPaymentToken(address to, uint256 amount) internal {
    IERC20 paymentToken = IERC20(paymentTokenAddress);
    paymentToken.safeTransfer(to, amount);
  }

  function _transferPaymentTokenFrom(
    address from,
    address to,
    uint256 amount
  ) internal {
    IERC20 paymentToken = IERC20(paymentTokenAddress);
    paymentToken.safeTransferFrom(from, to, amount);
  }

  function _approvePaymentToken(address to, uint256 amount) internal {
    IERC20 paymentToken = IERC20(paymentTokenAddress);
    paymentToken.approve(to, amount);
  }

  function _getPaymentTokenBalance(
    address _addr
  ) internal view returns (uint256) {
    IERC20 paymentToken = IERC20(paymentTokenAddress);
    return paymentToken.balanceOf(_addr);
  }

  function _addTotalWeekBv(uint256 weekNumber, uint256 amount) internal {
    totalWeeklyBv[weekNumber] += amount;
  }

  function _getWeeklyBv(uint256 weekNumber) internal view returns (uint256) {
    return totalWeeklyBv[weekNumber];
  }
}
