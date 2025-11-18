// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {VaultStorage} from "./VaultCore/VaultStorage.sol";
import {VaultHelper} from "./VaultCore/VaultHelper.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {ICoreManager} from "./interfaces/ICoreManager.sol";

/**
 * @title MultiAssetVault
 * @notice The main vault contract responsible for deposits, withdrawals, and asset pricing.
 * It manages DAI, PAXG, and WBTC reserves.
 */
contract MultiAssetVault is
    ReentrancyGuard,
    Ownable,
    VaultStorage,
    VaultHelper
{
    /**
     * @notice Initializes the Vault by setting all token addresses, external interfaces,
     * core contract, and initial administrators.
     */
    constructor(
        InitParams memory params
    ) VaultStorage(params) Ownable(params.initalOwner) {}

    /**
     * @notice Allows users to deposit DAI into the vault
     * The DAI is then partially swapped into reserve assets (PAXG, WBTC).
     * @param amountToDeposit The amount of DAI to deposit.
     */
    function deposit(uint256 amountToDeposit) external nonReentrant {
        require(amountToDeposit > 0, "Deposit amount must be > 0");

        // 1. Transfer DAI from user to vault
        _handleTransferFrom(msg.sender, address(this), amountToDeposit, DAI);

        // 2. Swap deposited DAI into PAXG and WBTC based on allocation if enabled
        _handleDepositedDai(amountToDeposit);
    }

    /**
     * @notice Allows users to redeem ARC and get dai
     */
    function redeem(uint256 amount) external nonReentrant {
        _handleRedeem(msg.sender, amount);
    }

    /**
     * @notice Allows users to redeem ARC and get dai
     */
    function redeemWithBaseTokens(uint256 amount) external nonReentrant {
        _handleRedeemWithBaseTokens(msg.sender, amount);
    }

    /**
     * @notice Calculates the current price of one ARC token in DAI equivalent.
     * @return arcPrice The price of 1 ARC token, denominated in DAI (1e18 precision).
     */
    function getPrice() public view returns (uint256 arcPrice) {
        return _getArcPrice();
    }

    /**
     * @notice Allows an authorized admin to withdraw all reserve assets from the vault.
     * This function is restricted by a 90-day grace period from deployment.
     */
    function emergencyWithdraw() external onlyOwner {
        // Corrected check: using the withdrawalEnabledTimestamp from VaultStorage
        require(
            block.timestamp <= withdrawalEnabledTimestamp,
            "Emergency withdrawal restricted during grace period"
        );
        _withdrawAll(msg.sender);
    }

    /**
     * @notice Allows the designated core contract to withdraw a specified amount of DAI.
     * @param amount The amount of DAI to withdraw.
     */
    function withdrawDai(uint256 amount) external onlyCore {
        require(amount > 0, "Withdrawal amount must be > 0");
        _handleInsufficientDai(amount);
        _handleTransfer(msg.sender, amount, DAI);
    }

    /**
     * @notice Updates the swap enabled status.
     * Can only be called by an admin.
     * @param enabled Boolean indicating whether swaps should be enabled or disabled.
     */
    function updateSwapEnabled(bool enabled) external {
        require(
            ICoreManager(coreContract).isManager(msg.sender),
            "Not authorized"
        );
        // maanger contract core
        isSwapEnabled = enabled;
    }

    /**
     * @notice update the fee receiver address
     */
    function updateFeeReceiver(address newFeeReceiver) external {
        require(msg.sender == feeReceiver, "Not authorized");
        require(newFeeReceiver != address(0), "Invalid address");
        require(!feeReceiverFlag, "Fee receiver already updated");

        feeReceiver = newFeeReceiver;
        feeReceiverFlag = true;
    }

    /**
     * @dev Override transferOwnership to allow only one transfer.
     */
    function transferOwnership(address newOwner) public override onlyOwner {
        if (ownershipFlag == false) {
            super.transferOwnership(newOwner);
            ownershipFlag = true;
        } else {
            revert("Ownership has already been transferred");
        }
    }
}
