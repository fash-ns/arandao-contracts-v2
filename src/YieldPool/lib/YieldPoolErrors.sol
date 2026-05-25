// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

library YieldPoolErrors {
    /// @dev amount must be greater than zero
    error ZeroAmount();

    /// @dev address argument must not be the zero address
    error ZeroAddress();

    /// @dev the stake has already been unstaked or never existed
    error StakeNotActive();

    /// @dev caller is not the owner of the given stake
    error NotStakeOwner();

    /// @dev there is no accrued reward to claim for this stake
    error NoRewardToClaim();

    /// @dev batchClaim was called with an empty stakeIds array
    error EmptyStakeIds();

    /// @dev caller is not the designated rewarder address
    error NotRewarder();
}
