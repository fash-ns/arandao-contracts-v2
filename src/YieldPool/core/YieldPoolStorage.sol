// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

abstract contract YieldPoolStorage {
    // ─── Structs ───────────────────────────────────────────────────────────────

    struct Stake {
        uint256 amount;
        // snapshot of accRewardPerShare at the time of the last interaction;
        // prevents double-claiming of historical rewards
        uint256 rewardDebt;
        address owner;
        bool active;
    }

    // ─── Constants ─────────────────────────────────────────────────────────────

    // 1e24 gives 24 decimal places of sub-unit precision when multiplying
    // token amounts by the accumulator, avoiding integer-division truncation
    uint256 internal constant PRECISION = 1e24;

    // ─── Tokens ────────────────────────────────────────────────────────────────

    /// @notice ARC token staked by users
    IERC20 public arcToken;

    /// @notice USDT token distributed as platform revenue
    IERC20 public usdtToken;

    // ─── Access ────────────────────────────────────────────────────────────────

    /// @notice Address authorised to call notifyReward (typically the treasury)
    address public rewarder;

    /// @notice Address of the ARC Core contract
    address public coreContract;

    // ─── Global Accumulator State ──────────────────────────────────────────────

    /// @notice Total ARC currently staked across all active positions
    uint256 public totalStaked;

    /// @notice Cumulative USDT earned per unit of ARC staked (scaled by PRECISION)
    uint256 public accRewardPerShare;

    /// @notice USDT held back when totalStaked == 0; flushed on the next stake
    uint256 public queuedRewards;

    // ─── Stake Registry ────────────────────────────────────────────────────────

    /// @notice Auto-incrementing stake ID counter; starts at 1
    uint256 public nextStakeId;

    /// @notice Stake data keyed by stake ID
    mapping(uint256 => Stake) public stakes;

    /// @notice Ordered list of stake IDs ever created by each address
    mapping(address => uint256[]) internal _userStakeIds;
}
