// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {ERC20Burnable} from "@openzeppelin/contracts/token/ERC20/extensions/ERC20Burnable.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {VaultStorage} from "./VaultStorage.sol";
import {SwapHelper} from "./SwapHelper.sol";

/**
 * @title VaultHelper
 * @notice Provides core internal logic, access control, and asset management functions
 */
abstract contract VaultHelper is VaultStorage, SwapHelper {
  using SafeERC20 for IERC20;

  /// @notice Ensures that only the designated core contract can call the function.
  modifier onlyCore() {
    _checkIsCoreContract(msg.sender);
    _;
  }

  /// @notice Ensures that only a contract admin can call the function.
  modifier onlyAdmin() {
    _checkIsAdmin(msg.sender);
    _;
  }

  /**
   * @notice Handles transferring tokens from a specific address using SafeERC20.safeTransferFrom.
   * @param from The address tokens are transferred from (must have prior approval).
   * @param to The address receiving the tokens.
   * @param amount The amount of tokens to transfer.
   * @param token The address of the token being transferred.
   */
  function _handleTransferFrom(
    address from,
    address to,
    uint256 amount,
    address token
  ) internal {
    IERC20(token).safeTransferFrom(from, to, amount);
  }

  /**
   * @notice Handles transferring tokens from the vault contract balance using SafeERC20.safeTransfer.
   * @param to The address receiving the tokens.
   * @param amount The amount of tokens to transfer.
   * @param token The address of the token being transferred.
   */
  function _handleTransfer(address to, uint256 amount, address token) internal {
    IERC20(token).safeTransfer(to, amount);
  }

  /**
   * @notice Calculates the total value of all reserve assets (DAI, PAXG, WBTC) held by the vault in DAI equivalent.
   * @dev Assumes price feeds return price in 1e18 format.
   * @return value The total reserve value denominated in DAI (1e18 precision).
   */
  function _getTotalReserveBalanceInDai()
    internal
    view
    returns (uint256 value)
  {
    // Balances
    uint256 daiBalance = IERC20(DAI).balanceOf(address(this));
    uint256 paxgBalance = IERC20(PAXG).balanceOf(address(this));
    uint256 wbtcBalance = IERC20(WBTC).balanceOf(address(this));

    // Prices
    uint256 paxgPrice = _priceFeed.getPaxgInDai();
    uint256 wbtcPrice = _priceFeed.getWbtcInDai();

    // Accumulate value
    value = daiBalance; // Start with native DAI balance
    value += (paxgBalance * paxgPrice) / 1e18; // ADD PAXG value
    value += (wbtcBalance * wbtcPrice) / 1e18; // ADD WBTC value
  }

  /**
   * @notice Retrieves the total supply of the DNM token.
   * @return The total supply of DNM.
   */
  function _getDnmTotalSupply() internal view returns (uint256) {
    return IERC20(DNM).totalSupply();
  }

  /**
   * @notice Requires the caller to be the designated core contract address.
   * @param caller The address attempting the call.
   */
  function _checkIsCoreContract(address caller) internal view {
    require(caller == coreContract, "Not authorized: not core");
  }

  /**
   * @notice Requires the caller to be an authorized admin address.
   * @param caller The address attempting the call.
   */
  function _checkIsAdmin(address caller) internal view {
    require(isAdmin[caller] == true, "Not authorized: not admin");
  }

  /**
   * @notice Withdraws all current balances of reserve assets (DAI, PAXG, WBTC) to a specified caller.
   * @dev This is typically an administrative or emergency function.
   * @param caller The address to transfer all balances to.
   */
  function _withdrawAll(address caller) internal {
    uint256 daiBalance = IERC20(DAI).balanceOf(address(this));
    if (daiBalance > 0) {
      _handleTransfer(caller, daiBalance, DAI);
    }

    uint256 paxgBalance = IERC20(PAXG).balanceOf(address(this));
    if (paxgBalance > 0) {
      _handleTransfer(caller, paxgBalance, PAXG);
    }

    uint256 wbtcBalance = IERC20(WBTC).balanceOf(address(this));
    if (wbtcBalance > 0) {
      _handleTransfer(caller, wbtcBalance, WBTC);
    }
  }

  /**
   * @notice Converts the deposited DAI into the target reserve tokens (PAXG and WBTC) based on allocation settings.
   * @param amount The total amount of DAI deposited to be swapped.
   */
  function _handleDepositedDai(uint256 amount) internal {
    uint256 paxgAmount = (amount * ALLOCATION_PAXG) / 100;
    uint256 wbtcAmount = (amount * ALLOCATION_WBTC) / 100;
    address to = address(this);

    // Swaps are now protected against zero amount in SwapHelper.
    _swapFromDAI(PAXG, paxgAmount, to);
    _swapFromDAI(WBTC, wbtcAmount, to);
  }

  function _getDnmPrice() internal view returns (uint256 dnmPrice) {
    uint256 totalReserveValue = _getTotalReserveBalanceInDai();
    uint256 dnmTotalSupply = _getDnmTotalSupply();

    if (dnmTotalSupply == 0) {
      // First deposit case: Price is 1 DAI (1e18)
      return 1e18;
    }

    // Price = Total Value / Total Supply of Shares
    // Denominated in DAI (1e18)
    dnmPrice = (totalReserveValue * 1e18) / dnmTotalSupply;
  }

  /**
   * @dev Destroys a `value` amount of dnm tokens from `account`, deducting from
   * the caller's allowance.
   */
  function _handleBurnDnm(address account, uint256 value) internal {
    ERC20Burnable(DNM).burnFrom(account, value);
  }

  /**
   * @notice Handles the redemption (withdrawal) of reserve assets by burning DNM shares.
   * This uses a proportional liquidation method:
   * 1. Calculates the user's share of all reserve assets.
   * 2. Swaps the PAXG and WBTC shares for DAI (into the vault).
   * 3. Calculates the total resulting DAI payout.
   * 4. Deducts the 3% fee from the total DAI.
   * 5. Transfers the net DAI to the user and the fee amount to the FEE_RECEIVER.
   * @param account The address redeeming the shares.
   * @param amount The amount of DNM tokens to redeem/burn.
   */
  function _handleRedeem(address account, uint256 amount) internal {
    require(amount > 0, "Redeem amount must be > 0");

    uint256 totalSup = _getDnmTotalSupply();
    require(totalSup > 0, "Cannot redeem from an empty vault");

    // 1. Calculate full pro-rata amounts of underlying assets
    uint256 initialDaiBalance = IERC20(DAI).balanceOf(address(this));
    uint256 paxgBalance = IERC20(PAXG).balanceOf(address(this));
    uint256 wbtcBalance = IERC20(WBTC).balanceOf(address(this));

    // Calculate full pro-rata amounts: (balance * share_amount) / total_supply
    uint256 daiProRata = (initialDaiBalance * amount) / totalSup;
    uint256 paxgProRata = (paxgBalance * amount) / totalSup;
    uint256 wbtcProRata = (wbtcBalance * amount) / totalSup;

    // Require at least some value to be redeemed
    require(
      daiProRata > 0 || paxgProRata > 0 || wbtcProRata > 0,
      "Redemption yields zero value"
    );

    _handleBurnDnm(account, amount);

    // 2. Swap Pro-Rata PAXG and WBTC shares to DAI, sending resulting DAI to the VAULT (address(this))
    if (paxgProRata > 0) {
      _swapToDAI(PAXG, paxgProRata, address(this));
    }

    if (wbtcProRata > 0) {
      _swapToDAI(WBTC, wbtcProRata, address(this));
    }

    // 3. Calculate total DAI acquired for the payout (accounting for the liquidation)
    uint256 finalDaiBalance = IERC20(DAI).balanceOf(address(this));

    // Calculate the DAI gained only from the proportional liquidation swaps (PAXG/WBTC -> DAI).
    // Since the swaps target the vault, finalDaiBalance should be >= initialDaiBalance.
    uint256 daiGainedFromSwaps = finalDaiBalance - initialDaiBalance;

    // totalDaiAcquiredForPayout is the sum of:
    // a) The user's share of the vault's initial DAI (daiProRata)
    // b) The DAI received from swapping the user's share of PAXG and WBTC (daiGainedFromSwaps)
    uint256 totalDaiAcquiredForPayout = daiProRata + daiGainedFromSwaps;

    // 4. Calculate Fee (3%) and Net Payout (97%)
    uint256 feeAmount = (totalDaiAcquiredForPayout * REDEEM_FEE_BPS) /
      BPS_DENOMINATOR;
    uint256 netDaiToPay = totalDaiAcquiredForPayout - feeAmount;

    // 5. Transfer the net calculated DAI to the user and the fee to the receiver
    if (netDaiToPay > 0) {
      _handleTransfer(account, netDaiToPay, DAI);
    }
    if (feeAmount > 0) {
      _handleTransfer(FEE_RECEIVER, feeAmount, DAI);
    }
  }

  /**
   * @notice Triggers a rebalancing swap to sell reserve assets (PAXG, WBTC) for DAI
   * when the vault's DAI balance is insufficient for a withdrawal.
   * It splits the DAI needed 50/50 between PAXG and WBTC sales, relying on SwapHelper for execution.
   * @param amountToWithdraw The total DAI amount required.
   */
  function _handleInsufficientDai(uint256 amountToWithdraw) internal {
    uint256 balance = IERC20(DAI).balanceOf(address(this));
    if (balance >= amountToWithdraw) {
      return;
    }

    // Calculate the DAI deficit. Requires amountToWithdraw > balance
    uint256 insufficientAmount = amountToWithdraw - balance;

    // Split the DAI needed 50/50
    uint256 daiNeededFromEach = insufficientAmount / 2;
    address to = address(this);

    // --- 1. Swap PAXG for 50% of the needed DAI using SwapHelper ---
    uint256 paxgBalance = IERC20(PAXG).balanceOf(address(this));

    // Use the helper to get the exact amount of DAI
    _swapForExactDAI(
      PAXG,
      daiNeededFromEach,
      paxgBalance, // Max PAXG input (to prevent overspending, use the full balance as max)
      to
    );

    // --- 2. Swap WBTC for the remaining needed DAI using SwapHelper ---
    // Handle odd amount splits: if insufficientAmount is odd, the remaining 1 wei is taken from WBTC.
    uint256 remainingDaiNeeded = insufficientAmount - daiNeededFromEach;
    uint256 wbtcBalance = IERC20(WBTC).balanceOf(address(this));

    // Use the helper to get the exact remaining amount of DAI
    _swapForExactDAI(
      WBTC,
      remainingDaiNeeded,
      wbtcBalance, // Max WBTC input (to prevent overspending, use the full balance as max)
      to
    );
  }
}
