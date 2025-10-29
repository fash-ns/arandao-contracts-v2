// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {VaultStorage} from "./VaultCore/VaultStorage.sol";
import {VaultHelper} from "./VaultCore/VaultHelper.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {Pausable} from "@openzeppelin/contracts/utils/Pausable.sol";

/**
 * @title MultiAssetVault
 * @notice The main vault contract responsible for deposits, withdrawals, and asset pricing.
 * It manages DAI, PAXG, and WBTC reserves.
 */
contract MultiAssetVault is
  Pausable,
  ReentrancyGuard,
  VaultStorage,
  VaultHelper
{
  /**
   * @notice Initializes the Vault by setting all token addresses, external interfaces,
   * core contract, and initial administrators.
   */
  constructor(InitParams memory params) VaultStorage(params) {}

  /**
   * @notice Allows users to deposit DAI into the vault
   * The DAI is then partially swapped into reserve assets (PAXG, WBTC).
   * @param amountToDeposit The amount of DAI to deposit.
   */
  function deposit(
    uint256 amountToDeposit
  ) external nonReentrant whenNotPaused {
    require(amountToDeposit > 0, "Deposit amount must be > 0");

    // 1. Transfer DAI from user to vault
    _handleTransferFrom(msg.sender, address(this), amountToDeposit, DAI);

    // 2. Swap deposited DAI into PAXG and WBTC based on allocation
    _handleDepositedDai(amountToDeposit);
  }

  /**
   * @notice Allows users to redeem dnm and get dai
   */
  function redeem(uint256 amount) external nonReentrant whenNotPaused {
    _handleRedeem(msg.sender, amount);
  }

  /**
   * @notice Calculates the current price of one DNM token in DAI equivalent.
   * @return dnmPrice The price of 1 DNM token, denominated in DAI (1e18 precision).
   */
  function getPrice() public view returns (uint256 dnmPrice) {
    return _getDnmPrice();
  }

  /**
   * @notice Allows an authorized admin to withdraw all reserve assets from the vault.
   * This function is restricted by a 90-day grace period from deployment.
   */
  function emergencyWithdraw() external onlyAdmin {
    // Corrected check: using the withdrawalEnabledTimestamp from VaultStorage
    require(
      block.timestamp <= withdrawalEnabledTimestamp,
      "Emergency withdrawal restricted during grace period"
    );
    _withdrawAll(msg.sender);
  }

  function setCoreAddress(address coreAddr) external onlyAdmin {
    require(coreContract == address(0), "Core contract address is already set");
    coreContract = coreAddr;
  }

  /**
   * @notice Allows the designated core contract to withdraw a specified amount of DAI.
   * @param amount The amount of DAI to withdraw.
   */
  function withdrawDai(uint256 amount) external onlyCore whenNotPaused {
    require(amount > 0, "Withdrawal amount must be > 0");
    _handleInsufficientDai(amount);
    _handleTransfer(msg.sender, amount, DAI);
  }

  /**
   * @notice Pauses all vault operations that are pausable (deposit, redeem, withdrawDai)
   * Can only be called by an admin.
   */
  function pause() external onlyAdmin {
    _pause();
  }

  /**
   * @notice Unpauses the vault operations
   * Can only be called by an admin.
   */
  function unpause() external onlyAdmin {
    _unpause();
  }
}
