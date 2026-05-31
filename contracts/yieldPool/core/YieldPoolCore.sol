// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

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

  function _activateLpMode(address _lpToken) internal {
    if (lpModeActive) revert YieldPoolErrors.LpModeAlreadyActive();
    if (
      _lpToken == address(0) ||
      _lpToken == address(arcToken) ||
      _lpToken == address(usdtToken)
    ) {
      revert YieldPoolErrors.InvalidLpToken();
    }

    lpModeActive = true;
    lpToken = _lpToken;
    // Anchor the eligibility sweep to today so _processEligibility never
    // iterates over days that predate LP mode.
    lastProcessedDay = block.timestamp / 1 days;

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
      rewardDebt: (amount * accRewardPerShare) / PRECISION,
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

  /// @dev Advances the reward checkpoint for `stakeId` and returns the claimable amount.
  ///      Does NOT transfer — callers that batch must consolidate the transfer.
  function _settleArcReward(uint256 stakeId) internal returns (uint256 reward) {
    Stake storage s = stakes[stakeId];
    if (!s.active) revert YieldPoolErrors.StakeNotActive();
    if (s.owner != msg.sender) revert YieldPoolErrors.NotStakeOwner();

    reward = _computeArcPending(s);
    if (reward > 0) {
      s.rewardDebt = (s.amount * accRewardPerShare) / PRECISION;
      emit YieldPoolEvents.Claimed(msg.sender, stakeId, reward);
    }
  }

  /// @dev Closes up to 20 ARC stakes in one transaction.  ARC is returned in a
  ///      single transfer; USDT rewards are consolidated and paid together (or frozen
  ///      atomically if the transfer fails).
  function _batchUnstake(uint256[] calldata stakeIds) internal {
    uint256 len = stakeIds.length;
    if (len == 0) revert YieldPoolErrors.EmptyStakeIds();
    if (len > 20) revert YieldPoolErrors.BatchTooLarge();

    uint256 totalArc;
    uint256 totalReward;
    uint256[] memory rewards = new uint256[](len);
    uint256 acc = accRewardPerShare; // cached; nonReentrant prevents updates mid-call

    for (uint256 i; i < len; ) {
      uint256 sid = stakeIds[i];
      Stake storage s = stakes[sid];
      if (!s.active) revert YieldPoolErrors.StakeNotActive();
      if (s.owner != msg.sender) revert YieldPoolErrors.NotStakeOwner();

      uint256 amount = s.amount;
      uint256 reward = (amount * acc) / PRECISION - s.rewardDebt;

      s.active = false;
      s.amount = 0;
      s.rewardDebt = 0;
      totalArc += amount;
      rewards[i] = reward;
      totalReward += reward;

      emit YieldPoolEvents.Unstaked(msg.sender, sid, amount);
      unchecked {
        ++i;
      }
    }
    totalStaked -= totalArc;

    arcToken.safeTransfer(msg.sender, totalArc);

    if (totalReward > 0) {
      bool transferred;
      try usdtToken.transfer(msg.sender, totalReward) returns (bool ok) {
        transferred = ok;
      } catch {}

      for (uint256 i; i < len; ) {
        uint256 r = rewards[i];
        if (r != 0) {
          if (transferred) {
            emit YieldPoolEvents.Claimed(msg.sender, stakeIds[i], r);
          } else {
            emit YieldPoolEvents.RewardFrozen(msg.sender, stakeIds[i], r);
          }
        }
        unchecked {
          ++i;
        }
      }
      if (!transferred) frozenRewards[msg.sender] += totalReward;
    }
  }

  /// @dev Claims rewards for multiple ARC stakes in one transaction.
  ///      Reward checkpoints are advanced per-stake; a single USDT transfer covers all.
  function _batchClaim(uint256[] calldata stakeIds) internal {
    uint256 len = stakeIds.length;
    if (len == 0) revert YieldPoolErrors.EmptyStakeIds();

    uint256 totalReward;
    for (uint256 i; i < len; ++i) {
      totalReward += _settleArcReward(stakeIds[i]);
    }
    if (totalReward == 0) revert YieldPoolErrors.NoRewardToClaim();
    usdtToken.safeTransfer(msg.sender, totalReward);
  }

  function _pendingArcReward(uint256 stakeId) internal view returns (uint256) {
    Stake storage s = stakes[stakeId];
    if (!s.active || s.amount == 0) return 0;
    return _computeArcPending(s);
  }

  function _computeArcPending(Stake storage s) internal view returns (uint256) {
    return (s.amount * accRewardPerShare) / PRECISION - s.rewardDebt;
  }

  // ══════════════════════════════════════════════════════════════════════════
  // §C  LP staking (Phase 2) — 7-day minimum eligibility
  // ══════════════════════════════════════════════════════════════════════════

  /// @dev Sweeps calendar days from lastProcessedDay+1 through today, moving any
  ///      ARC that has matured into the eligible pool and snapshotting the accumulator
  ///      so newly-enrolled stakes start from the correct baseline.
  ///
  ///      Iteration bound: days elapsed since the last call.  Because notifyReward is
  ///      expected to be called at least weekly this is typically ≤7 iterations.
  ///      The fast path exits in O(1) when no ARC is pending
  ///      (totalLpArcContributed == totalEligibleArc).
  function _processEligibility() internal {
    uint256 today = block.timestamp / 1 days;
    if (today <= lastProcessedDay) return;

    // Fast path: nothing is pending, skip the day loop.
    if (totalLpArcContributed == totalEligibleArc) {
      lastProcessedDay = today;
      return;
    }

    // Snapshot once — accEligibleRewardPerArc hasn't advanced since last call
    // (no epoch runs before this sweep), so every newly-eligible stake gets the
    // same baseline regardless of which specific day it fell on.
    uint256 snapshot = accEligibleRewardPerArc;

    for (uint256 day = lastProcessedDay + 1; day <= today; ) {
      uint256 arc = eligibilityByDay[day];
      if (arc > 0) {
        accEligibilitySnapshot[day] = snapshot;
        totalEligibleArc += arc;
        // All pending ARC is now enrolled; remaining days are provably empty.
        if (totalEligibleArc == totalLpArcContributed) {
          break;
        }
      }
      unchecked {
        ++day;
      }
    }

    lastProcessedDay = today;
  }

  /// @dev Lazily marks a stake as enrolled and sets its MasterChef rewardDebt to
  ///      the accumulator value captured when its eligibleDay was swept.  After this,
  ///      pending reward is the standard O(1) MasterChef formula.
  ///      Caller must have already called _processEligibility() and confirmed
  ///      lastProcessedDay >= s.eligibleDay.
  function _enrollIfNeeded(LpStake storage s) internal {
    if (!s.enrolled) {
      s.rewardDebt =
        (s.arcContributed * accEligibilitySnapshot[s.eligibleDay]) / PRECISION;
      s.enrolled = true;
    }
  }

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
    (uint256 arcUsed, uint256 usdtUsed, uint256 lpAmount) = uniswapRouter
      .addLiquidity(
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
    if (arcAmount > arcUsed)
      arcToken.safeTransfer(msg.sender, arcAmount - arcUsed);
    if (usdtAmount > usdtUsed)
      usdtToken.safeTransfer(msg.sender, usdtAmount - usdtUsed);

    // eligibleDay = floor((now + MIN_LP_STAKE_DURATION) / 1 day):
    // the first calendar day on which this stake's ARC counts toward epochs.
    uint256 eligibleDay = (block.timestamp + MIN_LP_STAKE_DURATION) / 1 days;

    totalLpArcContributed += arcUsed;
    eligibilityByDay[eligibleDay] += arcUsed;

    uint256 lpStakeId = nextLpStakeId++;
    lpStakes[lpStakeId] = LpStake({
      lpAmount: lpAmount,
      arcContributed: arcUsed,
      rewardDebt: 0, // meaningless until enrolled
      eligibleDay: eligibleDay,
      owner: user,
      active: true,
      enrolled: false
    });
    _userLpStakeIds[user].push(lpStakeId);

    emit YieldPoolEvents.LpStaked(user, lpStakeId, lpAmount, arcUsed, usdtUsed);
  }

  /// @dev Advances the reward checkpoint for `lpStakeId` and returns the claimable amount.
  ///      Caller must have already called _processEligibility().
  ///      Does NOT transfer — callers that batch must consolidate the transfer.
  function _settleLpReward(
    uint256 lpStakeId
  ) internal returns (uint256 reward) {
    LpStake storage s = lpStakes[lpStakeId];
    if (!s.active) revert YieldPoolErrors.LpStakeNotActive();
    if (s.owner != msg.sender) revert YieldPoolErrors.NotLpStakeOwner();
    if (lastProcessedDay < s.eligibleDay)
      revert YieldPoolErrors.StakeNotYetEligible();

    _enrollIfNeeded(s);

    reward =
      (s.arcContributed * accEligibleRewardPerArc) / PRECISION -
      s.rewardDebt;
    if (reward > 0) {
      // CEI: advance checkpoint before transfer.
      s.rewardDebt = (s.arcContributed * accEligibleRewardPerArc) / PRECISION;
      emit YieldPoolEvents.LpRewardClaimed(msg.sender, lpStakeId, reward);
    }
  }

  function _claimLpReward(uint256 lpStakeId) internal {
    _processEligibility();
    uint256 reward = _settleLpReward(lpStakeId);
    if (reward == 0) revert YieldPoolErrors.NoRewardToClaim();
    usdtToken.safeTransfer(msg.sender, reward);
  }

  /// @dev Claims rewards for multiple LP stakes in one transaction.
  ///      _processEligibility runs once; reward checkpoints advanced per-stake;
  ///      a single USDT transfer covers all.
  function _batchClaimLpReward(uint256[] calldata lpStakeIds) internal {
    uint256 len = lpStakeIds.length;
    if (len == 0) revert YieldPoolErrors.EmptyStakeIds();
    if (len > 20) revert YieldPoolErrors.BatchTooLarge();

    _processEligibility();

    uint256 totalReward;
    for (uint256 i; i < len; ++i) {
      totalReward += _settleLpReward(lpStakeIds[i]);
    }
    if (totalReward == 0) revert YieldPoolErrors.NoRewardToClaim();
    usdtToken.safeTransfer(msg.sender, totalReward);
  }

  /// @dev Core cancel work for a single LP stake.
  ///      Caller must have already called _processEligibility().
  ///      Removes liquidity via the router (ARC + USDT go directly to msg.sender),
  ///      clears state, and returns the accrued reward without transferring it —
  ///      callers are responsible for the USDT transfer so batches can consolidate.
  ///
  ///      Eligibility accounting:
  ///        • Before eligible  — ARC lives in eligibilityByDay[eligibleDay]; remove it there.
  ///        • After eligible   — ARC lives in totalEligibleArc; remove it there.
  function _executeCancelLpStake(
    uint256 lpStakeId,
    uint256 arcAmountMin,
    uint256 usdtAmountMin
  ) internal returns (uint256 reward) {
    LpStake storage s = lpStakes[lpStakeId];
    if (!s.active) revert YieldPoolErrors.LpStakeNotActive();
    if (s.owner != msg.sender) revert YieldPoolErrors.NotLpStakeOwner();

    uint256 lpAmount = s.lpAmount;
    uint256 arcContributed = s.arcContributed;
    uint256 eligibleDay = s.eligibleDay;
    bool eligible = lastProcessedDay >= eligibleDay;

    if (eligible) {
      _enrollIfNeeded(s);
      reward =
        (s.arcContributed * accEligibleRewardPerArc) / PRECISION -
        s.rewardDebt;
    }

    // Effects — clear stake state first (CEI).
    s.active = false;
    s.lpAmount = 0;
    s.arcContributed = 0;
    s.rewardDebt = 0;

    totalLpArcContributed -= arcContributed;
    if (eligible) {
      totalEligibleArc -= arcContributed;
    } else {
      eligibilityByDay[eligibleDay] -= arcContributed;
    }

    // Interaction — router removes liquidity and sends tokens directly to caller.
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
    // NOTE: LpRewardClaimed / RewardFrozen is emitted by the caller after
    //       it knows whether the USDT transfer succeeded or was frozen.
  }

  /// @dev Cancels a single LP stake.
  ///      _processEligibility runs first to keep rewards up-to-date.
  ///      If USDT is paused or blacklisted the reward is frozen in frozenRewards
  ///      so the user can reclaim it later via claimFrozenRewards(); the LP
  ///      liquidity is always returned regardless of USDT state.
  function _cancelLpStake(
    uint256 lpStakeId,
    uint256 arcAmountMin,
    uint256 usdtAmountMin
  ) internal {
    _processEligibility();
    uint256 reward = _executeCancelLpStake(
      lpStakeId,
      arcAmountMin,
      usdtAmountMin
    );

    if (reward > 0) {
      try usdtToken.transfer(msg.sender, reward) returns (bool ok) {
        if (ok) {
          emit YieldPoolEvents.LpRewardClaimed(msg.sender, lpStakeId, reward);
        } else {
          frozenRewards[msg.sender] += reward;
          emit YieldPoolEvents.RewardFrozen(msg.sender, lpStakeId, reward);
        }
      } catch {
        frozenRewards[msg.sender] += reward;
        emit YieldPoolEvents.RewardFrozen(msg.sender, lpStakeId, reward);
      }
    }
  }

  /// @dev Cancels up to 20 LP stakes in one transaction.  _processEligibility runs
  ///      once; each cancel is delegated to _executeCancelLpStake (keeping per-iteration
  ///      stack depth low); all accrued USDT rewards are consolidated into a single
  ///      safeTransfer at the end.
  function _batchCancelLpStake(
    uint256[] calldata lpStakeIds,
    uint256[] calldata arcAmountMins,
    uint256[] calldata usdtAmountMins
  ) internal {
    uint256 len = lpStakeIds.length;
    if (len == 0) revert YieldPoolErrors.EmptyStakeIds();
    if (len > 20) revert YieldPoolErrors.BatchTooLarge();
    if (arcAmountMins.length != len || usdtAmountMins.length != len) {
      revert YieldPoolErrors.ArrayLengthMismatch();
    }

    _processEligibility();

    uint256 totalReward;
    for (uint256 i; i < len; ) {
      uint256 lpStakeId = lpStakeIds[i];
      uint256 reward = _executeCancelLpStake(
        lpStakeId,
        arcAmountMins[i],
        usdtAmountMins[i]
      );
      if (reward > 0) {
        totalReward += reward;
        emit YieldPoolEvents.LpRewardClaimed(msg.sender, lpStakeId, reward);
      }
      unchecked {
        ++i;
      }
    }

    // safeTransfer reverts the entire tx on failure, which also rolls back all
    // LpRewardClaimed events emitted above — so events only survive on success.
    if (totalReward > 0) usdtToken.safeTransfer(msg.sender, totalReward);
  }

  function _pendingLpReward(uint256 lpStakeId) internal view returns (uint256) {
    LpStake storage s = lpStakes[lpStakeId];
    if (!s.active || s.arcContributed == 0) return 0;
    return _computeLpPending(s);
  }

  /// @dev O(1) pending calculation.
  ///      Returns 0 if the stake's eligibleDay has not yet been swept (which implies
  ///      no epochs have been created for it — correct because _processEligibility always
  ///      runs before any epoch is written).
  ///      After sweeping, uses the snapshot to give the stake a zero baseline for all
  ///      epochs that pre-date its eligibility, then applies the standard MasterChef formula.
  function _computeLpPending(
    LpStake storage s
  ) internal view returns (uint256) {
    if (lastProcessedDay < s.eligibleDay) return 0;

    uint256 baseDebt =
      s.enrolled
        ? s.rewardDebt
        : (s.arcContributed * accEligibilitySnapshot[s.eligibleDay]) /
          PRECISION;

    return (s.arcContributed * accEligibleRewardPerArc) / PRECISION - baseDebt;
  }

  // ══════════════════════════════════════════════════════════════════════════
  // §D  Reward injection (mode-aware)
  // ══════════════════════════════════════════════════════════════════════════

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
        accRewardPerShare += (toDistribute * PRECISION) / totalStaked;
      }
    } else {
      // ── LP pool ───────────────────────────────────────────────────
      // Advance eligibility before creating the epoch so that any ARC
      // that matured today is included in the denominator.
      _processEligibility();

      if (totalEligibleArc == 0) {
        queuedLpRewards += amount;
      } else {
        uint256 toDistribute = amount;
        if (queuedLpRewards > 0) {
          toDistribute += queuedLpRewards;
          emit YieldPoolEvents.QueuedRewardFlushed(queuedLpRewards);
          queuedLpRewards = 0;
        }
        accEligibleRewardPerArc +=
          (toDistribute * PRECISION) / totalEligibleArc;
      }
    }

    emit YieldPoolEvents.RewardNotified(msg.sender, amount);
  }
}
