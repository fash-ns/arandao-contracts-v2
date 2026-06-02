// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IUniswapV2Router02} from "../lib/IUniswapV2.sol";

abstract contract YieldPoolStorage {
    // ─── Structs ───────────────────────────────────────────────────────────────

    struct Stake {
        uint256 amount;
        uint256 rewardDebt; // snapshot of accRewardPerShare; prevents double-claiming
        address owner;
        bool active;
    }

    struct LpStake {
        uint256 lpAmount; // LP tokens held by this contract for this position
        uint256 arcContributed; // ARC actually consumed by Uniswap — the reward weight
        uint256 rewardDebt; // MasterChef debt against accEligibleRewardPerArc (valid after enrollment)
        uint256 eligibleDay; // first calendar day (floor(ts/1day)) this stake may earn epoch rewards
        address owner;
        bool active;
        bool enrolled; // true once eligibleDay has been swept by _processEligibility
    }

    // ─── Constants ─────────────────────────────────────────────────────────────

    /// @dev 1e24: 24 digits of sub-unit precision avoiding integer-division dust
    uint256 internal constant PRECISION = 1e24;

    /// @dev Minimum time a stake must be held before it earns LP epoch rewards.
    uint256 internal constant MIN_LP_STAKE_DURATION = 7 days;

    /// @dev Window after deployment during which batchStakeFor may seed Phase-1 stakes.
    uint256 internal constant BATCH_STAKE_WINDOW = 1 days;

    // ─── Tokens ────────────────────────────────────────────────────────────────

    IERC20 public arcToken;
    IERC20 public usdtToken;

    /// @notice Timestamp the contract was deployed; upper-bounds the batchStakeFor window.
    uint256 public immutable deployTime;

    // ─── Access ────────────────────────────────────────────────────────────────

    /// @notice Authorised to call notifyReward (treasury / multisig)
    address public rewarder;

    /// @notice Authorised to call activateLpMode exactly once
    address public lpActivator;

    // ─── Mode flag ─────────────────────────────────────────────────────────────

    /// @notice false = ARC-only staking; true = LP staking (set permanently by activateLpMode)
    bool public lpModeActive;

    // ─── LP infrastructure ─────────────────────────────────────────────────────

    IUniswapV2Router02 public uniswapRouter;

    /// @notice ARC/USDT Uniswap V2 LP token; set permanently by activateLpMode
    address public lpToken;

    // ══════════════════════════════════════════════════════════════════════════
    // ARC staking pool
    // ══════════════════════════════════════════════════════════════════════════

    uint256 public totalStaked;
    uint256 public accRewardPerShare;
    uint256 public queuedRewards;

    uint256 public nextStakeId;
    mapping(uint256 => Stake) public stakes;
    mapping(address => uint256[]) internal _userStakeIds;
    mapping(address => uint256) public frozenRewards;

    // ══════════════════════════════════════════════════════════════════════════
    // LP staking pool — epoch-eligible MasterChef accumulator
    // ══════════════════════════════════════════════════════════════════════════

    /// @notice Total ARC across all active LP stakes (eligible + pending).
    uint256 public totalLpArcContributed;

    /// @notice ARC from stakes whose eligibleDay has been processed; denominator for epochs.
    uint256 public totalEligibleArc;

    /// @notice MasterChef accumulator that advances only when epochs are created.
    uint256 public accEligibleRewardPerArc;

    /// @notice USDT queued while totalEligibleArc == 0; flushed into the next epoch.
    uint256 public queuedLpRewards;

    /// @dev ARC amount keyed by the calendar day it transitions from pending to eligible.
    ///      eligibilityByDay[day] += arcUsed on stake; -= arcUsed on cancel-before-eligible.
    mapping(uint256 => uint256) public eligibilityByDay;

    /// @dev Snapshot of accEligibleRewardPerArc at the moment each calendar day was first swept.
    ///      Serves as the zero-earning baseline for stakes whose eligibleDay == that day.
    mapping(uint256 => uint256) public accEligibilitySnapshot;

    /// @dev Last calendar day (floor(timestamp/1day)) swept by _processEligibility.
    uint256 public lastProcessedDay;

    uint256 public nextLpStakeId;
    mapping(uint256 => LpStake) public lpStakes;
    mapping(address => uint256[]) internal _userLpStakeIds;
}
