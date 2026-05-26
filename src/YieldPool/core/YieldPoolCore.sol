// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {YieldPoolStorage} from "./YieldPoolStorage.sol";
import {YieldPoolErrors} from "../lib/YieldPoolErrors.sol";
import {YieldPoolEvents} from "../lib/YieldPoolEvents.sol";

abstract contract YieldPoolCore is YieldPoolStorage {
    using SafeERC20 for IERC20;

    // ─── Stake / Unstake ───────────────────────────────────────────────────────

    /// @dev Opens a new stake position for `user` with `amount` ARC.
    function _stake(address user, uint256 amount) internal {
        if (amount == 0) revert YieldPoolErrors.ZeroAmount();

        // Effects first (CEI): all state is written before the external call so that
        // any token hook or re-entry attempt sees a fully-consistent state.
        totalStaked += amount;

        uint256 stakeId = nextStakeId++;
        stakes[stakeId] =
            Stake({amount: amount, rewardDebt: amount * accRewardPerShare / PRECISION, owner: user, active: true});
        _userStakeIds[user].push(stakeId);

        // Interaction last (CEI).
        arcToken.safeTransferFrom(msg.sender, address(this), amount);
        emit YieldPoolEvents.Staked(user, stakeId, amount);
    }

    /// @dev Closes `stakeId`, returns ARC to the caller, and pays out any
    ///      accrued USDT reward in the same transaction.
    function _unstake(uint256 stakeId) internal {
        Stake storage s = stakes[stakeId];
        if (!s.active) revert YieldPoolErrors.StakeNotActive();
        if (s.owner != msg.sender) revert YieldPoolErrors.NotStakeOwner();

        uint256 amount = s.amount;
        uint256 reward = _computePending(s);

        // Write all state before external calls (CEI).
        s.active = false;
        s.amount = 0;
        s.rewardDebt = 0;
        totalStaked -= amount;

        arcToken.safeTransfer(msg.sender, amount);
        emit YieldPoolEvents.Unstaked(msg.sender, stakeId, amount);

        if (reward > 0) {
            try usdtToken.transfer(msg.sender, reward) returns (bool success) {
                if (success) {
                    emit YieldPoolEvents.Claimed(msg.sender, stakeId, reward);
                } else {
                    frozenRewards[msg.sender] += reward;
                    emit YieldPoolEvents.RewardFrozen(msg.sender, stakeId, reward);
                }
            } catch {
                frozenRewards[msg.sender] += reward;
                emit YieldPoolEvents.RewardFrozen(msg.sender, stakeId, reward);
            }
        }
    }

    // ─── Reward Collection ─────────────────────────────────────────────────────

    /// @dev Claims USDT reward for a single stake and transfers it immediately.
    function _claim(uint256 stakeId) internal {
        uint256 reward = _settleReward(stakeId);
        if (reward == 0) revert YieldPoolErrors.NoRewardToClaim();
        usdtToken.safeTransfer(msg.sender, reward);
    }

    /// @dev Updates the reward checkpoint for `stakeId` and returns the accrued
    ///      reward without transferring. Designed for use in batch-claim loops
    ///      so that the final USDT transfer can be consolidated into one call.
    function _settleReward(uint256 stakeId) internal returns (uint256 reward) {
        Stake storage s = stakes[stakeId];
        if (!s.active) revert YieldPoolErrors.StakeNotActive();
        if (s.owner != msg.sender) revert YieldPoolErrors.NotStakeOwner();

        reward = _computePending(s);
        if (reward > 0) {
            // Advance the checkpoint to prevent double-claiming.
            s.rewardDebt = s.amount * accRewardPerShare / PRECISION;
            emit YieldPoolEvents.Claimed(msg.sender, stakeId, reward);
        }
    }

    // ─── Reward Injection ──────────────────────────────────────────────────────

    /// @dev Receives `amount` USDT and updates the global accumulator.
    ///
    ///      If no ARC is currently staked, the USDT is queued in `queuedRewards`
    ///      rather than credited immediately. On the next call where totalStaked > 0,
    ///      the full queued balance is distributed together with the new deposit.
    function _notifyReward(uint256 amount) internal {
        if (amount == 0) revert YieldPoolErrors.ZeroAmount();

        // Interaction first: receive USDT before touching accounting (CEI).
        // Credits are only written after the transfer succeeds.
        usdtToken.safeTransferFrom(msg.sender, address(this), amount);

        if (totalStaked == 0) {
            queuedRewards += amount;
        } else {
            // Fold any previously queued balance into this distribution so it
            // reaches current stakers instead of sitting unclaimable.
            uint256 toDistribute = amount;
            if (queuedRewards > 0) {
                toDistribute += queuedRewards;
                emit YieldPoolEvents.QueuedRewardDistributed(queuedRewards);
                queuedRewards = 0;
            }
            accRewardPerShare += toDistribute * PRECISION / totalStaked;
        }

        emit YieldPoolEvents.RewardNotified(msg.sender, amount);
    }

    // ─── View Helpers ──────────────────────────────────────────────────────────

    /// @dev Returns the USDT reward claimable by the owner of `stakeId` right now.
    function _pendingReward(uint256 stakeId) internal view returns (uint256) {
        Stake storage s = stakes[stakeId];
        if (!s.active || s.amount == 0) return 0;
        return _computePending(s);
    }

    // ─── Pure Math ─────────────────────────────────────────────────────────────

    /// @dev pending = (amount × accRewardPerShare / PRECISION) − rewardDebt
    function _computePending(Stake storage s) private view returns (uint256) {
        return s.amount * accRewardPerShare / PRECISION - s.rewardDebt;
    }
}
