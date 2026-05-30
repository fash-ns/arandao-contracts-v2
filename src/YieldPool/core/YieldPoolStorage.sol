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
        uint256 lpAmount;       // LP tokens held by this contract for this position
        uint256 arcContributed; // ARC actually consumed by Uniswap — the reward weight
        uint256 rewardDebt;     // snapshot of accLpRewardPerShare × arcContributed
        address owner;
        bool active;
    }

    // ─── Constants ─────────────────────────────────────────────────────────────

    /// @dev 1e24: 24 digits of sub-unit precision avoiding integer-division dust
    uint256 internal constant PRECISION = 1e24;

    // ─── Tokens ────────────────────────────────────────────────────────────────

    IERC20 public arcToken;
    IERC20 public usdtToken;

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
    // LP staking pool — MasterChef accumulator over ARC contributed
    // ══════════════════════════════════════════════════════════════════════════

    /// @notice Total ARC currently contributed across all active LP stakes
    uint256 public totalLpArcContributed;

    /// @notice Accumulated USDT reward per unit of ARC contributed × PRECISION
    uint256 public accLpRewardPerShare;

    /// @notice USDT queued while totalLpArcContributed == 0; flushed into the next notify
    uint256 public queuedLpRewards;

    uint256 public nextLpStakeId;
    mapping(uint256 => LpStake) public lpStakes;
    mapping(address => uint256[]) internal _userLpStakeIds;
}
