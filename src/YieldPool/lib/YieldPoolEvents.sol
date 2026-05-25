// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

library YieldPoolEvents {
    /// @dev emitted when a user opens a new stake position
    event Staked(address user, uint256 stakeId, uint256 amount);

    /// @dev emitted when a user closes a stake position (ARC returned)
    event Unstaked(address user, uint256 stakeId, uint256 amount);

    /// @dev emitted whenever USDT rewards are transferred to a user
    event Claimed(address user, uint256 stakeId, uint256 reward);

    /// @dev emitted when the rewarder deposits platform revenue into the pool
    event RewardNotified(address notifier, uint256 amount);

    /// @dev emitted when rewards queued during a zero-staker period are flushed into accRewardPerShare
    event QueuedRewardDistributed(uint256 amount);

    /// @dev emitted when the rewarder recovers queued rewards before any staker joins
    event QueuedRewardRescued(address rewarder, uint256 amount);

}
