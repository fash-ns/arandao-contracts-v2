// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

library YieldPoolEvents {
  // ─── ARC staking ───────────────────────────────────────────────────────────

  /// @dev emitted when a user opens a new ARC stake position
  event Staked(address indexed user, uint256 indexed stakeId, uint256 amount);

  /// @dev emitted when a user closes an ARC stake position (ARC returned)
  event Unstaked(address indexed user, uint256 indexed stakeId, uint256 amount);

  /// @dev emitted whenever USDT rewards are transferred to an ARC staker
  event Claimed(address indexed user, uint256 indexed stakeId, uint256 reward);

  /// @dev emitted when a USDT reward transfer fails on unstake (token paused / blacklisted);
  ///      the amount is tracked in frozenRewards and claimable once USDT is operational
  event RewardFrozen(
    address indexed user,
    uint256 indexed stakeId,
    uint256 amount
  );

  // ─── Mode switch ───────────────────────────────────────────────────────────

  /// @dev emitted when the lpActivator enables LP-only staking mode
  event LpModeActivated(address indexed lpToken);

  // ─── Shared reward injection ────────────────────────────────────────────────

  /// @dev emitted when the rewarder deposits USDT into the active pool
  event RewardNotified(address indexed notifier, uint256 amount);

  /// @dev emitted when queued rewards (deposited while no stakers existed) are flushed
  event QueuedRewardFlushed(uint256 amount);

  // ─── LP staking ────────────────────────────────────────────────────────────

  /// @dev emitted when a user provides ARC+USDT liquidity and opens an LP stake
  event LpStaked(
    address indexed user,
    uint256 indexed lpStakeId,
    uint256 lpAmount,
    uint256 arcContributed,
    uint256 usdtContributed
  );

  /// @dev emitted when an LP stake is cancelled and underlying tokens are returned
  event LpUnstaked(
    address indexed user,
    uint256 indexed lpStakeId,
    uint256 arcReturned,
    uint256 usdtReturned
  );

  /// @dev emitted when USDT reward is paid to an LP staker (on claim or cancel)
  event LpRewardClaimed(
    address indexed user,
    uint256 indexed lpStakeId,
    uint256 reward
  );
}
