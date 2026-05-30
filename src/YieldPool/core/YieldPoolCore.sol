// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {YieldPoolStorage} from "./YieldPoolStorage.sol";
import {YieldPoolErrors} from "../lib/YieldPoolErrors.sol";
import {YieldPoolEvents} from "../lib/YieldPoolEvents.sol";

abstract contract YieldPoolCore is YieldPoolStorage {
    using SafeERC20 for IERC20;

    // ══════════════════════════════════════════════════════════════════════════
    // §A  Mode switch
    // ══════════════════════════════════════════════════════════════════════════

    /// @dev Permanently switches the pool from ARC-only to LP mode.
    ///      After this call, new ARC stakes are blocked and LP stakes are open.
    ///      Existing ARC stakers stop earning new rewards (their accRewardPerShare
    ///      is frozen at this point) but may still unstake and claim what they earned.
    function _activateLpMode(address _lpToken) internal {
        if (lpModeActive) revert YieldPoolErrors.LpModeAlreadyActive();
        if (
            _lpToken == address(0) ||
            _lpToken == address(arcToken) ||
            _lpToken == address(usdtToken)
        ) revert YieldPoolErrors.InvalidLpToken();

        lpModeActive = true;
        lpToken = _lpToken;

        emit YieldPoolEvents.LpModeActivated(_lpToken);
    }

    // ══════════════════════════════════════════════════════════════════════════
    // §B  ARC staking (Phase 1)
    // ══════════════════════════════════════════════════════════════════════════

    function _stake(address user, uint256 amount) internal {
        if (amount == 0) revert YieldPoolErrors.ZeroAmount();
        if (lpModeActive) revert YieldPoolErrors.ArcStakingDisabled();

        totalStaked += amount;
        uint256 stakeId = nextStakeId++;
        stakes[stakeId] = Stake({
            amount: amount,
            rewardDebt: amount * accRewardPerShare / PRECISION,
            owner: user,
            active: true
        });
        _userStakeIds[user].push(stakeId);

        arcToken.safeTransferFrom(msg.sender, address(this), amount);
        emit YieldPoolEvents.Staked(user, stakeId, amount);
    }

    function _unstake(uint256 stakeId) internal {
        Stake storage s = stakes[stakeId];
        if (!s.active) revert YieldPoolErrors.StakeNotActive();
        if (s.owner != msg.sender) revert YieldPoolErrors.NotStakeOwner();

        uint256 amount = s.amount;
        uint256 reward = _computeArcPending(s);

        // CEI: effects before interactions.
        s.active = false;
        s.amount = 0;
        s.rewardDebt = 0;
        totalStaked -= amount;

        arcToken.safeTransfer(msg.sender, amount);
        emit YieldPoolEvents.Unstaked(msg.sender, stakeId, amount);

        if (reward > 0) {
            try usdtToken.transfer(msg.sender, reward) returns (bool ok) {
                if (ok) {
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

    function _claim(uint256 stakeId) internal {
        uint256 reward = _settleArcReward(stakeId);
        if (reward == 0) revert YieldPoolErrors.NoRewardToClaim();
        usdtToken.safeTransfer(msg.sender, reward);
    }

    /// @dev Advances the reward checkpoint for `stakeId` and returns the reward.
    ///      Does NOT transfer — callers that batch must consolidate the transfer.
    function _settleArcReward(uint256 stakeId) internal returns (uint256 reward) {
        Stake storage s = stakes[stakeId];
        if (!s.active) revert YieldPoolErrors.StakeNotActive();
        if (s.owner != msg.sender) revert YieldPoolErrors.NotStakeOwner();

        reward = _computeArcPending(s);
        if (reward > 0) {
            s.rewardDebt = s.amount * accRewardPerShare / PRECISION;
            emit YieldPoolEvents.Claimed(msg.sender, stakeId, reward);
        }
    }

    function _pendingArcReward(uint256 stakeId) internal view returns (uint256) {
        Stake storage s = stakes[stakeId];
        if (!s.active || s.amount == 0) return 0;
        return _computeArcPending(s);
    }

    function _computeArcPending(Stake storage s) internal view returns (uint256) {
        return s.amount * accRewardPerShare / PRECISION - s.rewardDebt;
    }

    // ══════════════════════════════════════════════════════════════════════════
    // §C  LP staking (Phase 2)
    // ══════════════════════════════════════════════════════════════════════════

    /// @dev Pulls `arcAmount` ARC and `usdtAmount` USDT from the caller, deposits them
    ///      into the Uniswap V2 ARC/USDT pool via the router, and records the resulting
    ///      LP tokens and the actual ARC consumed as a new LP stake.
    ///      Any tokens not used by Uniswap (due to ratio rounding) are refunded.
    function _addLiquidityAndStake(
        address user,
        uint256 arcAmount,
        uint256 usdtAmount,
        uint256 arcAmountMin,
        uint256 usdtAmountMin
    ) internal {
        if (!lpModeActive) revert YieldPoolErrors.LpModeNotActive();
        if (arcAmount == 0 || usdtAmount == 0) revert YieldPoolErrors.ZeroAmount();

        // Pull tokens from the caller.
        arcToken.safeTransferFrom(msg.sender, address(this), arcAmount);
        usdtToken.safeTransferFrom(msg.sender, address(this), usdtAmount);

        // Grant the router exactly the amounts it may consume.
        arcToken.forceApprove(address(uniswapRouter), arcAmount);
        usdtToken.forceApprove(address(uniswapRouter), usdtAmount);

        // Add liquidity; LP tokens land directly in this contract.
        (uint256 arcUsed, uint256 usdtUsed, uint256 lpAmount) = uniswapRouter.addLiquidity(
            address(arcToken),
            address(usdtToken),
            arcAmount,
            usdtAmount,
            arcAmountMin,
            usdtAmountMin,
            address(this),
            block.timestamp + 300
        );

        // Revoke any remaining router allowance and refund unused tokens.
        arcToken.forceApprove(address(uniswapRouter), 0);
        usdtToken.forceApprove(address(uniswapRouter), 0);
        if (arcAmount > arcUsed) arcToken.safeTransfer(msg.sender, arcAmount - arcUsed);
        if (usdtAmount > usdtUsed) usdtToken.safeTransfer(msg.sender, usdtAmount - usdtUsed);

        // Record the LP stake. Reward weight = ARC actually consumed (not LP tokens).
        totalLpArcContributed += arcUsed;
        uint256 lpStakeId = nextLpStakeId++;
        lpStakes[lpStakeId] = LpStake({
            lpAmount: lpAmount,
            arcContributed: arcUsed,
            rewardDebt: arcUsed * accLpRewardPerShare / PRECISION,
            owner: user,
            active: true
        });
        _userLpStakeIds[user].push(lpStakeId);

        emit YieldPoolEvents.LpStaked(user, lpStakeId, lpAmount, arcUsed, usdtUsed);
    }

    /// @dev Claims accrued USDT reward for an active LP stake.
    function _claimLpReward(uint256 lpStakeId) internal {
        LpStake storage s = lpStakes[lpStakeId];
        if (!s.active) revert YieldPoolErrors.LpStakeNotActive();
        if (s.owner != msg.sender) revert YieldPoolErrors.NotLpStakeOwner();

        uint256 reward = _computeLpPending(s);
        if (reward == 0) revert YieldPoolErrors.NoRewardToClaim();

        // CEI: advance checkpoint before transfer.
        s.rewardDebt = s.arcContributed * accLpRewardPerShare / PRECISION;

        usdtToken.safeTransfer(msg.sender, reward);
        emit YieldPoolEvents.LpRewardClaimed(msg.sender, lpStakeId, reward);
    }

    /// @dev Cancels an LP stake: removes Uniswap V2 liquidity and returns ARC + USDT to
    ///      the caller. Any accrued USDT reward is also paid out atomically.
    ///
    ///      Flow (CEI):
    ///        1. Validate & read state.
    ///        2. Clear the LP stake (effects).
    ///        3. Approve LP to router, call removeLiquidity, transfer reward (interactions).
    function _cancelLpStake(
        uint256 lpStakeId,
        uint256 arcAmountMin,
        uint256 usdtAmountMin
    ) internal {
        LpStake storage s = lpStakes[lpStakeId];
        if (!s.active) revert YieldPoolErrors.LpStakeNotActive();
        if (s.owner != msg.sender) revert YieldPoolErrors.NotLpStakeOwner();

        uint256 lpAmount = s.lpAmount;
        uint256 arcContributed = s.arcContributed;
        uint256 reward = _computeLpPending(s);

        // Effects.
        s.active = false;
        s.lpAmount = 0;
        s.arcContributed = 0;
        s.rewardDebt = 0;
        totalLpArcContributed -= arcContributed;

        // Interactions: router pulls LP tokens from us and sends ARC+USDT directly to caller.
        IERC20(lpToken).forceApprove(address(uniswapRouter), lpAmount);
        (uint256 arcOut, uint256 usdtOut) = uniswapRouter.removeLiquidity(
            address(arcToken),
            address(usdtToken),
            lpAmount,
            arcAmountMin,
            usdtAmountMin,
            msg.sender,
            block.timestamp + 300
        );
        IERC20(lpToken).forceApprove(address(uniswapRouter), 0);

        emit YieldPoolEvents.LpUnstaked(msg.sender, lpStakeId, arcOut, usdtOut);

        if (reward > 0) {
            usdtToken.safeTransfer(msg.sender, reward);
            emit YieldPoolEvents.LpRewardClaimed(msg.sender, lpStakeId, reward);
        }
    }

    function _pendingLpReward(uint256 lpStakeId) internal view returns (uint256) {
        LpStake storage s = lpStakes[lpStakeId];
        if (!s.active || s.arcContributed == 0) return 0;
        return _computeLpPending(s);
    }

    function _computeLpPending(LpStake storage s) internal view returns (uint256) {
        return s.arcContributed * accLpRewardPerShare / PRECISION - s.rewardDebt;
    }

    // ══════════════════════════════════════════════════════════════════════════
    // §D  Reward injection (mode-aware)
    // ══════════════════════════════════════════════════════════════════════════

    /// @dev Receives `amount` USDT from the rewarder and routes it to whichever
    ///      pool is currently active.
    ///
    ///      ARC mode: updates accRewardPerShare (or queues if totalStaked == 0).
    ///      LP  mode: updates accLpRewardPerShare (or queues if totalLpArcContributed == 0).
    function _notifyReward(uint256 amount) internal {
        if (amount == 0) revert YieldPoolErrors.ZeroAmount();

        usdtToken.safeTransferFrom(msg.sender, address(this), amount);

        if (!lpModeActive) {
            // ── ARC pool ──────────────────────────────────────────────────
            if (totalStaked == 0) {
                queuedRewards += amount;
            } else {
                uint256 toDistribute = amount;
                if (queuedRewards > 0) {
                    toDistribute += queuedRewards;
                    emit YieldPoolEvents.QueuedRewardFlushed(queuedRewards);
                    queuedRewards = 0;
                }
                accRewardPerShare += toDistribute * PRECISION / totalStaked;
            }
        } else {
            // ── LP pool ───────────────────────────────────────────────────
            if (totalLpArcContributed == 0) {
                queuedLpRewards += amount;
            } else {
                uint256 toDistribute = amount;
                if (queuedLpRewards > 0) {
                    toDistribute += queuedLpRewards;
                    emit YieldPoolEvents.QueuedRewardFlushed(queuedLpRewards);
                    queuedLpRewards = 0;
                }
                accLpRewardPerShare += toDistribute * PRECISION / totalLpArcContributed;
            }
        }

        emit YieldPoolEvents.RewardNotified(msg.sender, amount);
    }
}
