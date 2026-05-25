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
 *  rewarder      single address allowed to call notifyReward and rotate access addresses
 *  coreContract  only address allowed to stake on behalf of a user
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
 *  If no stakers are expected, the rewarder can recover queued funds via
 *  rescueQueuedRewards() before any staker joins.
 */
contract YieldPool is YieldPoolCore, ReentrancyGuard {
    using SafeERC20 for IERC20;

    // ─── Constructor ───────────────────────────────────────────────────────────

    /**
     * @param _arcToken     Address of the ARC ERC-20 token users stake
     * @param _usdtToken    Address of the USDT ERC-20 token distributed as rewards
     * @param _rewarder     Address authorised to deposit revenue (treasury / multisig)
     * @param _coreContract Address of the ARC Core contract allowed to stake on behalf of users
     */
    constructor(address _arcToken, address _usdtToken, address _rewarder, address _coreContract) {
        if (
            _arcToken == address(0) || _usdtToken == address(0) || _rewarder == address(0)
                || _coreContract == address(0)
        ) {
            revert YieldPoolErrors.ZeroAddress();
        }
        arcToken = IERC20(_arcToken);
        usdtToken = IERC20(_usdtToken);
        rewarder = _rewarder;
        coreContract = _coreContract;
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
     * @notice Opens a stake position on behalf of `user`.
     * @dev    Only callable by coreContract. The user must have approved ARC
     *         to this contract (not to coreContract).
     * @param  user   Address of the beneficiary staker
     * @param  amount ARC to lock (must have prior approval from `coreContract` to this contract)
     */
    function stakeByCoreContract(address user, uint256 amount) external nonReentrant {
        if (msg.sender != coreContract) revert YieldPoolErrors.OnlyCoreContract();
        if (user == address(0)) revert YieldPoolErrors.ZeroAddress();
        _stake(user, amount);
    }

    /**
     * @notice Closes a stake position and returns ARC + any accrued USDT reward.
     * @param  stakeId ID of the position to close
     */
    function unstake(uint256 stakeId) external nonReentrant {
        _unstake(stakeId);
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
