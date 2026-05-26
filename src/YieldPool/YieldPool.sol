// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {YieldPoolCore} from "./core/YieldPoolCore.sol";
import {YieldPoolErrors} from "./lib/YieldPoolErrors.sol";
import {YieldPoolEvents} from "./lib/YieldPoolEvents.sol";

/**
 * @title YieldPool
 * @notice ARC staking vault that distributes USDT platform revenue pro-rata
 *         using the accumulator model (same as MasterChef / Synthetix).
 *
 * Architecture
 * ────────────
 *  YieldPoolErrors  (library)   — custom error definitions
 *  YieldPoolEvents  (library)   — event definitions
 *  core/YieldPoolStorage        — state variables + Stake struct
 *  core/YieldPoolCore           — all internal business logic
 *  YieldPool        (concrete)  — external entry points
 *
 * Access
 * ──────
 *  rewarder  single address allowed to call notifyReward
 *
 * Key invariant
 * ─────────────
 *  For any active stake:
 *      claimable = stake.amount × accRewardPerShare / PRECISION − stake.rewardDebt
 *
 * Known design trade-off — queued reward epoch
 * ─────────────────────────────────────────────
 *  If notifyReward is called while totalStaked == 0, the deposited USDT is held in
 *  queuedRewards. On the next notifyReward call where totalStaked > 0, the queued
 *  balance is folded into the distribution and reaches current stakers.
 */
contract YieldPool is YieldPoolCore, ReentrancyGuard {
    using SafeERC20 for IERC20;

    // ─── Constructor ───────────────────────────────────────────────────────────

    /**
     * @param _arcToken  Address of the ARC ERC-20 token users stake
     * @param _usdtToken Address of the USDT ERC-20 token distributed as rewards
     * @param _rewarder  Address authorised to deposit revenue (treasury / multisig)
     */
    constructor(address _arcToken, address _usdtToken, address _rewarder) {
        if (_arcToken == address(0) || _usdtToken == address(0) || _rewarder == address(0)) {
            revert YieldPoolErrors.ZeroAddress();
        }
        arcToken = IERC20(_arcToken);
        usdtToken = IERC20(_usdtToken);
        rewarder = _rewarder;
        nextStakeId = 1;
    }

    // ─── User: Staking ─────────────────────────────────────────────────────────

    /**
     * @notice Opens a new, independent stake position.
     * @dev    Stake positions are immutable — to add more ARC, call stake() again.
     *         To change an amount, unstake() and restake().
     * @param  amount ARC to lock (must have prior approval to this contract)
     */
    function stake(uint256 amount) external nonReentrant {
        _stake(msg.sender, amount);
    }

    /**
     * @notice Closes a stake position and returns ARC + any accrued USDT reward.
     * @param  stakeId ID of the position to close
     */
    function unstake(uint256 stakeId) external nonReentrant {
        _unstake(stakeId);
    }

    /**
     * @notice Closes multiple stake positions in one transaction.
     * @dev    Optimised: one ARC transfer and one USDT transfer cover all positions.
     *         Maximum 20 stakeIds per call. All stakeIds must belong to msg.sender and
     *         be active; the call reverts on the first invalid entry so no partial state
     *         is committed. If the consolidated USDT transfer fails the full reward is
     *         frozen and recoverable via claimFrozenRewards() — ARC is always returned.
     * @param  stakeIds Array of stake IDs to close (max 20)
     */
    function batchUnstake(uint256[] calldata stakeIds) external nonReentrant {
        uint256 len = stakeIds.length;
        if (len == 0) revert YieldPoolErrors.EmptyStakeIds();
        if (len > 20) revert YieldPoolErrors.BatchTooLarge();

        uint256 totalArc;
        uint256 totalReward;
        uint256[] memory rewards = new uint256[](len);
        // Cache storage read: accRewardPerShare won't change during this call (nonReentrant)
        uint256 acc = accRewardPerShare;

        // ── Effects: settle all positions, accumulate totals ───────────────────
        for (uint256 i; i < len;) {
            uint256 stakeId = stakeIds[i];
            Stake storage s = stakes[stakeId];
            if (!s.active) revert YieldPoolErrors.StakeNotActive();
            if (s.owner != msg.sender) revert YieldPoolErrors.NotStakeOwner();

            uint256 amount = s.amount;
            uint256 reward = amount * acc / PRECISION - s.rewardDebt;

            s.active = false;
            s.amount = 0;
            s.rewardDebt = 0;
            totalArc += amount;
            rewards[i] = reward;
            totalReward += reward;

            emit YieldPoolEvents.Unstaked(msg.sender, stakeId, amount);
            unchecked { ++i; }
        }
        // Single SSTORE instead of one per position
        totalStaked -= totalArc;

        // ── Interactions: one ARC transfer for all positions ───────────────────
        arcToken.safeTransfer(msg.sender, totalArc);

        // ── Interactions: one USDT transfer (or freeze) for all rewards ────────
        if (totalReward > 0) {
            bool transferred;
            try usdtToken.transfer(msg.sender, totalReward) returns (bool ok) {
                transferred = ok;
            } catch {}

            for (uint256 i; i < len;) {
                uint256 reward = rewards[i];
                if (reward != 0) {
                    if (transferred) {
                        emit YieldPoolEvents.Claimed(msg.sender, stakeIds[i], reward);
                    } else {
                        emit YieldPoolEvents.RewardFrozen(msg.sender, stakeIds[i], reward);
                    }
                }
                unchecked { ++i; }
            }
            if (!transferred) {
                frozenRewards[msg.sender] += totalReward;
            }
        }
    }

    // ─── User: Rewards ─────────────────────────────────────────────────────────

    /**
     * @notice Claims all accrued USDT reward for a single stake position.
     * @param  stakeId ID of the stake to claim from
     */
    function claim(uint256 stakeId) external nonReentrant {
        _claim(stakeId);
    }

    /**
     * @notice Claims accrued USDT reward for multiple stake positions in one tx.
     * @dev    All provided stakeIds must belong to msg.sender and must be active.
     *         A single USDT transfer is issued at the end, saving gas.
     *         The call reverts if any stakeId is inactive — filter to active IDs before calling.
     * @param  stakeIds Array of stake IDs to collect from
     */
    function batchClaim(uint256[] calldata stakeIds) external nonReentrant {
        uint256 len = stakeIds.length;
        if (len == 0) revert YieldPoolErrors.EmptyStakeIds();

        uint256 totalReward;
        for (uint256 i; i < len; ++i) {
            // _settleReward updates rewardDebt and emits Claimed per stakeId.
            totalReward += _settleReward(stakeIds[i]);
        }

        if (totalReward == 0) revert YieldPoolErrors.NoRewardToClaim();
        usdtToken.safeTransfer(msg.sender, totalReward);
    }

    // ─── Protocol: Revenue Injection ───────────────────────────────────────────

    /**
     * @notice Deposits USDT platform revenue into the pool for pro-rata distribution.
     * @dev    Caller must have approved this contract for `amount` USDT.
     *         If no ARC is currently staked, the reward is queued — see the contract-level
     *         doc comment for the implications of depositing while totalStaked == 0.
     * @param  amount USDT to distribute
     */
    function notifyReward(uint256 amount) external nonReentrant {
        if (msg.sender != rewarder) revert YieldPoolErrors.NotRewarder();
        _notifyReward(amount);
    }

    // ─── User: Frozen Reward Recovery ─────────────────────────────────────────

    /**
     * @notice Claims USDT rewards that were frozen during a previous unstake due to
     *         the USDT token being paused or blacklisting this contract.
     * @dev    Call after USDT is operational again. Reverts if caller has no frozen balance.
     */
    function claimFrozenRewards() external nonReentrant {
        uint256 amount = frozenRewards[msg.sender];
        if (amount == 0) revert YieldPoolErrors.NoFrozenRewards();
        frozenRewards[msg.sender] = 0;
        usdtToken.safeTransfer(msg.sender, amount);
    }

    // ─── View Functions ────────────────────────────────────────────────────────

    /**
     * @notice Returns the USDT reward currently claimable for `stakeId`.
     * @param  stakeId Stake position to query
     * @return Claimable USDT (0 if stake is inactive or has no accrued reward)
     */
    function pendingReward(uint256 stakeId) external view returns (uint256) {
        return _pendingReward(stakeId);
    }

    /**
     * @notice Returns all stake IDs ever opened by `user`, including inactive ones.
     * @dev    Filter by stakes[id].active off-chain before passing to batchClaim.
     * @param  user Address to query
     * @return Array of stake IDs in creation order
     */
    function getUserStakeIds(address user) external view returns (uint256[] memory) {
        return _userStakeIds[user];
    }
}
