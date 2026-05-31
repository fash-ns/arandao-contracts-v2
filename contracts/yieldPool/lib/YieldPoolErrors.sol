// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

library YieldPoolErrors {
    // ─── Shared ────────────────────────────────────────────────────────────────

    /// @dev amount argument must be greater than zero
    error ZeroAmount();

  /// @dev address argument must not be the zero address
  error ZeroAddress();

    /// @dev there is no accrued reward to claim
    error NoRewardToClaim();

    /// @dev caller is not the designated rewarder address
    error NotRewarder();

  /// @dev caller has no frozen rewards to claim
  error NoFrozenRewards();

    /// @dev batchClaim / batchUnstake was called with an empty array
    error EmptyStakeIds();

    /// @dev batchUnstake / batchCancelLpStake was called with more than the allowed number of ids
    error BatchTooLarge();

    /// @dev parallel arrays passed to a batch function must have the same length
    error ArrayLengthMismatch();

    // ─── ARC staking ───────────────────────────────────────────────────────────

    /// @dev the stake has already been unstaked or never existed
    error StakeNotActive();

    /// @dev caller is not the owner of the given stake
    error NotStakeOwner();

    /// @dev LP mode is active; new pure-ARC stakes are no longer accepted
    error ArcStakingDisabled();

    // ─── Mode switch ───────────────────────────────────────────────────────────

    /// @dev caller is not the lpActivator
    error NotLpActivator();

    /// @dev activateLpMode has already been called; it can only be called once
    error LpModeAlreadyActive();

    /// @dev the provided LP token address is invalid
    error InvalidLpToken();

    // ─── LP staking ────────────────────────────────────────────────────────────

    /// @dev LP mode is not yet active; addLiquidityAndStake / claimLpReward / cancelLpStake are disabled
    error LpModeNotActive();

    /// @dev the LP stake has already been cancelled or never existed
    error LpStakeNotActive();

    /// @dev caller is not the owner of the given LP stake
    error NotLpStakeOwner();

    /// @dev the LP stake has not yet satisfied the minimum staking duration for rewards
    error StakeNotYetEligible();
}
