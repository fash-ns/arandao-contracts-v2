// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {YieldPoolCore} from "./core/YieldPoolCore.sol";
import {YieldPoolErrors} from "./lib/YieldPoolErrors.sol";
import {YieldPoolEvents} from "./lib/YieldPoolEvents.sol";
import {IUniswapV2Router02} from "./lib/IUniswapV2.sol";

/**
 * @title YieldPool
 * @notice Two-phase USDT-reward staking vault.
 *
 * Phase 1 — ARC staking
 * ─────────────────────
 *  Users stake ARC tokens and earn USDT platform revenue pro-rata using the
 *  MasterChef accumulator model (accRewardPerShare over totalStaked ARC).
 *
 * Phase 2 — LP staking  (activated once by the lpActivator role)
 * ───────────────────────────────────────────────────────────────
 *  The lpActivator calls activateLpMode(lpToken) exactly once, providing the
 *  address of the pre-existing Uniswap V2 ARC/USDT LP token.  After this:
 *    • New pure-ARC stakes are permanently disabled.
 *    • Existing ARC stakers stop earning new rewards (accRewardPerShare freezes)
 *      but retain all rewards earned up to the switch and may unstake / claim freely.
 *    • Users call addLiquidityAndStake(arcAmount, usdtAmount, …) to deposit both
 *      tokens; the contract adds them to the Uniswap V2 pool via the router, holds
 *      the resulting LP tokens, and tracks the ARC actually consumed as the reward
 *      weight for that position (same accumulator model, different denominator).
 *    • LP stakes must be held for a minimum of 7 days before they become eligible to
 *      earn epoch rewards.  USDT notified before any stake is eligible is queued and
 *      flushed automatically into the first epoch that has eligible ARC.
 *    • cancelLpStake removes liquidity via the router and returns ARC + USDT to the
 *      user, along with any accrued USDT reward.
 *    • notifyReward now feeds the LP pool accumulator instead of the ARC pool.
 *
 * Architecture
 * ────────────
 *  lib/YieldPoolErrors     — custom errors
 *  lib/YieldPoolEvents     — events
 *  lib/IUniswapV2          — minimal V2 router interface
 *  core/YieldPoolStorage   — state layout + Stake / LpStake structs
 *  core/YieldPoolCore      — all internal logic
 *  YieldPool               — external entry points (this file)
 */
contract YieldPool is YieldPoolCore, ReentrancyGuard {
    using SafeERC20 for IERC20;

    // ─── Constructor ───────────────────────────────────────────────────────────

    /**
     * @param _arcToken       ARC ERC-20 token address
     * @param _usdtToken      USDT ERC-20 token address
     * @param _rewarder       Address authorised to call notifyReward
     * @param _lpActivator    Address authorised to call activateLpMode (once)
     * @param _uniswapRouter  Uniswap V2 Router02 address
     */
    constructor(
        address _arcToken,
        address _usdtToken,
        address _rewarder,
        address _lpActivator,
        address _uniswapRouter
    ) {
        if (
            _arcToken == address(0) || _usdtToken == address(0) || _rewarder == address(0) || _lpActivator == address(0)
                || _uniswapRouter == address(0)
        ) revert YieldPoolErrors.ZeroAddress();

        arcToken = IERC20(_arcToken);
        usdtToken = IERC20(_usdtToken);
        rewarder = _rewarder;
        lpActivator = _lpActivator;
        uniswapRouter = IUniswapV2Router02(_uniswapRouter);

        deployTime = block.timestamp;

        nextStakeId = 1;
        nextLpStakeId = 1;
    }

    // ══════════════════════════════════════════════════════════════════════════
    // §1  Mode switch
    // ══════════════════════════════════════════════════════════════════════════

    /**
     * @notice Permanently enables LP staking mode and disables new ARC stakes.
     * @dev    Can only be called once by the lpActivator.
     *         After this call notifyReward feeds the LP pool and addLiquidityAndStake
     *         becomes available.  Existing ARC stakers can still unstake and claim.
     * @param  _lpToken  Address of the Uniswap V2 ARC/USDT LP token
     */
    function activateLpMode(address _lpToken) external {
        if (msg.sender != lpActivator) revert YieldPoolErrors.NotLpActivator();
        _activateLpMode(_lpToken);
    }

    // ══════════════════════════════════════════════════════════════════════════
    // §2  ARC staking
    // ══════════════════════════════════════════════════════════════════════════

    /**
     * @notice Opens a new ARC stake position.
     * @dev    Reverts once LP mode is active.  Each call creates an independent
     *         position; stake again to add more ARC.
     * @param  amount  ARC to lock (caller must have approved this contract)
     */
    function stake(uint256 amount) external nonReentrant {
        _stake(msg.sender, amount);
    }

    /**
     * @notice Seeds Phase-1 ARC stakes on behalf of a list of users.
     * @dev    Only callable within 1 day of deployment and before LP mode is active.
     *         The caller funds the whole batch: the summed ARC is pulled from msg.sender
     *         (who must have approved this contract), while each position is owned by the
     *         matching `users` entry. Has no access control — see _batchStakeFor for the
     *         rationale and trade-off. The two arrays must have equal, non-zero length.
     * @param  users    Addresses to credit with the new stake positions
     * @param  amounts  ARC to stake for each user (parallel to `users`)
     */
    function batchStakeFor(address[] calldata users, uint256[] calldata amounts) external nonReentrant {
        _batchStakeFor(users, amounts);
    }

    /**
     * @notice Closes an ARC stake position and returns ARC + any accrued USDT reward.
     * @param  stakeId  Position to close
     */
    function unstake(uint256 stakeId) external nonReentrant {
        _unstake(stakeId);
    }

    /**
     * @notice Closes up to 20 ARC stake positions in a single transaction.
     * @dev    All stakeIds must belong to msg.sender and be active; the call reverts
     *         on the first invalid entry — no partial state is committed.
     *         If the consolidated USDT transfer fails, rewards are frozen and
     *         recoverable via claimFrozenRewards().
     * @param  stakeIds  Array of stake IDs to close (max 20)
     */
    function batchUnstake(uint256[] calldata stakeIds) external nonReentrant {
        _batchUnstake(stakeIds);
    }

    /**
     * @notice Claims accrued USDT reward for a single ARC stake.
     * @param  stakeId  Stake to claim from
     */
    function claim(uint256 stakeId) external nonReentrant {
        _claim(stakeId);
    }

    /**
     * @notice Claims accrued USDT reward for multiple ARC stakes in one transaction.
     * @param  stakeIds  Stake IDs to collect from (all must be active and owned by caller)
     */
    function batchClaim(uint256[] calldata stakeIds) external nonReentrant {
        _batchClaim(stakeIds);
    }

    /**
     * @notice Claims USDT rewards that were frozen during a previous unstake
     *         because the USDT token was paused or had blacklisted this contract.
     */
    function claimFrozenRewards() external nonReentrant {
        uint256 amount = frozenRewards[msg.sender];
        if (amount == 0) revert YieldPoolErrors.NoFrozenRewards();
        frozenRewards[msg.sender] = 0;
        usdtToken.safeTransfer(msg.sender, amount);
    }

    // ══════════════════════════════════════════════════════════════════════════
    // §3  LP staking
    // ══════════════════════════════════════════════════════════════════════════

    /**
     * @notice Deposits ARC + USDT as Uniswap V2 liquidity and opens an LP stake.
     * @dev    Only available after activateLpMode is called.
     *         The contract adds liquidity via the router and holds the LP tokens.
     *         Reward weight = ARC actually consumed by Uniswap (not the LP token count).
     *         Any tokens not used by Uniswap due to ratio rounding are refunded.
     *         The stake must be held for at least 7 days before it becomes eligible to
     *         earn USDT epoch rewards; claimLpReward reverts before that window passes.
     * @param  arcAmount      ARC to deposit (caller must have approved this contract)
     * @param  usdtAmount     USDT to deposit (caller must have approved this contract)
     * @param  arcAmountMin   Minimum ARC Uniswap must consume (slippage guard)
     * @param  usdtAmountMin  Minimum USDT Uniswap must consume (slippage guard)
     */
    function addLiquidityAndStake(uint256 arcAmount, uint256 usdtAmount, uint256 arcAmountMin, uint256 usdtAmountMin)
        external
        nonReentrant
    {
        _addLiquidityAndStake(msg.sender, arcAmount, usdtAmount, arcAmountMin, usdtAmountMin);
    }

    /**
     * @notice Claims accrued USDT reward for an active LP stake.
     * @dev    Reverts with StakeNotYetEligible if the 7-day minimum hold period has
     *         not elapsed since the stake was opened.
     * @param  lpStakeId  LP stake to claim from
     */
    function claimLpReward(uint256 lpStakeId) external nonReentrant {
        _claimLpReward(lpStakeId);
    }

    /**
     * @notice Claims accrued USDT reward for multiple LP stakes in one transaction.
     * @dev    All lpStakeIds must belong to msg.sender and be active.  All must have
     *         passed their 7-day eligibility window; the call reverts on the first
     *         ineligible entry.  A single USDT transfer covers all collected rewards.
     * @param  lpStakeIds  LP stake IDs to collect from (max 20)
     */
    function batchClaimLpReward(uint256[] calldata lpStakeIds) external nonReentrant {
        _batchClaimLpReward(lpStakeIds);
    }

    /**
     * @notice Cancels an LP stake: removes Uniswap V2 liquidity and returns
     *         ARC + USDT to the caller.  Any accrued USDT reward is paid out
     *         in the same transaction.
     * @param  lpStakeId      LP stake to cancel
     * @param  arcAmountMin   Minimum ARC to receive when removing liquidity (slippage guard)
     * @param  usdtAmountMin  Minimum USDT to receive when removing liquidity (slippage guard)
     */
    function cancelLpStake(uint256 lpStakeId, uint256 arcAmountMin, uint256 usdtAmountMin) external nonReentrant {
        _cancelLpStake(lpStakeId, arcAmountMin, usdtAmountMin);
    }

    /**
     * @notice Cancels multiple LP stakes in a single transaction.
     * @dev    All lpStakeIds must belong to msg.sender and be active.
     *         Liquidity is removed per-stake via the router (ARC + USDT sent directly to
     *         caller each time); all accrued USDT rewards are consolidated into a single
     *         transfer at the end.  The three arrays must have equal length.
     * @param  lpStakeIds      LP stake IDs to cancel (max 20)
     * @param  arcAmountMins   Per-stake minimum ARC to receive when removing liquidity
     * @param  usdtAmountMins  Per-stake minimum USDT to receive when removing liquidity
     */
    function batchCancelLpStake(
        uint256[] calldata lpStakeIds,
        uint256[] calldata arcAmountMins,
        uint256[] calldata usdtAmountMins
    ) external nonReentrant {
        _batchCancelLpStake(lpStakeIds, arcAmountMins, usdtAmountMins);
    }

    // ══════════════════════════════════════════════════════════════════════════
    // §4  Reward injection
    // ══════════════════════════════════════════════════════════════════════════

    /**
     * @notice Deposits USDT platform revenue for distribution to stakers.
     * @dev    In ARC mode feeds the ARC accumulator; in LP mode feeds the LP accumulator.
     *         Caller must have approved this contract for `amount` USDT.
     * @param  amount  USDT to distribute
     */
    function notifyReward(uint256 amount) external nonReentrant {
        if (msg.sender != rewarder) revert YieldPoolErrors.NotRewarder();
        _notifyReward(amount);
    }

    // ══════════════════════════════════════════════════════════════════════════
    // §5  View functions
    // ══════════════════════════════════════════════════════════════════════════

    /// @notice USDT reward currently claimable for an ARC stake.
    function pendingReward(uint256 stakeId) external view returns (uint256) {
        return _pendingArcReward(stakeId);
    }

    /// @notice USDT reward currently accrued for an LP stake.
    function pendingLpReward(uint256 lpStakeId) external view returns (uint256) {
        return _pendingLpReward(lpStakeId);
    }

    /// @notice All ARC stake IDs ever opened by `user` (including closed ones).
    function getUserStakeIds(address user) external view returns (uint256[] memory) {
        return _userStakeIds[user];
    }

    /// @notice All LP stake IDs ever opened by `user` (including cancelled ones).
    function getUserLpStakeIds(address user) external view returns (uint256[] memory) {
        return _userLpStakeIds[user];
    }
}
