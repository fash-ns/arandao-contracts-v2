// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {Test, Vm} from "forge-std/Test.sol";
import {YieldPool} from "../../src/YieldPool/YieldPool.sol";
import {YieldPoolErrors} from "../../src/YieldPool/lib/YieldPoolErrors.sol";
import {YieldPoolEvents} from "../../src/YieldPool/lib/YieldPoolEvents.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

// ─── Mock tokens ──────────────────────────────────────────────────────────────

contract MockARC is ERC20 {
    constructor() ERC20("ARC Token", "ARC") {}

    function mint(address to, uint256 amount) external {
        _mint(to, amount);
    }
}

contract MockUSDT is ERC20 {
    constructor() ERC20("Tether USD", "USDT") {}

    function decimals() public pure override returns (uint8) {
        return 6;
    }

    function mint(address to, uint256 amount) external {
        _mint(to, amount);
    }
}

// ─── Mock Uniswap V2 LP token ─────────────────────────────────────────────────

contract MockLP is ERC20 {
    constructor() ERC20("Uni-V2 ARC/USDT", "UNI-V2") {}

    function mint(address to, uint256 amount) external {
        _mint(to, amount);
    }
}

// ─── Mock Uniswap V2 Router ───────────────────────────────────────────────────
//
// Simplified behaviour:
//  addLiquidity    — consumes both tokens, mints LP = amountADesired.
//  removeLiquidity — burns LP (via transferFrom), returns tokens proportionally.
// Token order is always (ARC, USDT) in every call from YieldPool.

contract MockUniswapV2Router {
    MockLP public lp;

    uint256 public reserveArc;
    uint256 public reserveUsdt;
    uint256 public totalLp;

    constructor(address _lp) {
        lp = MockLP(_lp);
    }

    function addLiquidity(
        address tokenA,
        address tokenB,
        uint256 amountADesired,
        uint256 amountBDesired,
        uint256, // amountAMin — ignored in mock
        uint256, // amountBMin — ignored in mock
        address to,
        uint256 // deadline — ignored in mock
    ) external returns (uint256 amountA, uint256 amountB, uint256 liquidity) {
        IERC20(tokenA).transferFrom(msg.sender, address(this), amountADesired);
        IERC20(tokenB).transferFrom(msg.sender, address(this), amountBDesired);

        // LP = arcAmount for simplicity; math works out on removal.
        liquidity = amountADesired;
        reserveArc += amountADesired;
        reserveUsdt += amountBDesired;
        totalLp += liquidity;

        lp.mint(to, liquidity);
        return (amountADesired, amountBDesired, liquidity);
    }

    function removeLiquidity(
        address tokenA,
        address tokenB,
        uint256 liquidity,
        uint256, // amountAMin — ignored in mock
        uint256, // amountBMin — ignored in mock
        address to,
        uint256 // deadline — ignored in mock
    )
        external
        returns (uint256 amountA, uint256 amountB)
    {
        IERC20(address(lp)).transferFrom(msg.sender, address(this), liquidity);

        amountA = liquidity * reserveArc / totalLp;
        amountB = liquidity * reserveUsdt / totalLp;

        reserveArc -= amountA;
        reserveUsdt -= amountB;
        totalLp -= liquidity;

        IERC20(tokenA).transfer(to, amountA);
        IERC20(tokenB).transfer(to, amountB);
    }
}

// ─── Base test harness ─────────────────────────────────────────────────────────

contract YieldPoolTest is Test {
    // ── constants ──
    uint256 internal constant ARC_UNIT = 1e18;
    uint256 internal constant USDT_UNIT = 1e6;
    uint256 internal constant PRECISION = 1e24;

    // ── contracts ──
    YieldPool internal pool;
    MockARC internal arc;
    MockUSDT internal usdt;
    MockLP internal lp;
    MockUniswapV2Router internal router;

    // ── actors ──
    address internal alice = makeAddr("alice");
    address internal bob = makeAddr("bob");
    address internal charlie = makeAddr("charlie");
    address internal dave = makeAddr("dave");
    address internal rewarder = makeAddr("rewarder");
    address internal lpActivatorAddr = makeAddr("lpActivator");
    address internal attacker = makeAddr("attacker");

    // ─── Setup ────────────────────────────────────────────────────────────────

    function setUp() public virtual {
        arc = new MockARC();
        usdt = new MockUSDT();
        lp = new MockLP();
        router = new MockUniswapV2Router(address(lp));

        pool = new YieldPool(address(arc), address(usdt), rewarder, lpActivatorAddr, address(router));

        // Fund users with ARC
        arc.mint(alice, 1_000_000 * ARC_UNIT);
        arc.mint(bob, 1_000_000 * ARC_UNIT);
        arc.mint(charlie, 1_000_000 * ARC_UNIT);
        arc.mint(dave, 1_000_000 * ARC_UNIT);
        arc.mint(attacker, 1_000_000 * ARC_UNIT);

        // Fund rewarder with USDT
        usdt.mint(rewarder, 10_000_000 * USDT_UNIT);

        // Pre-approve pool for ARC staking
        _approveArc(alice);
        _approveArc(bob);
        _approveArc(charlie);
        _approveArc(dave);
        _approveArc(attacker);
        _approveUsdt(rewarder);
    }

    // ─── Helpers ──────────────────────────────────────────────────────────────

    function _approveArc(address who) internal {
        vm.prank(who);
        arc.approve(address(pool), type(uint256).max);
    }

    function _approveUsdt(address who) internal {
        vm.prank(who);
        usdt.approve(address(pool), type(uint256).max);
    }

    function _stake(address who, uint256 amount) internal returns (uint256 stakeId) {
        vm.prank(who);
        pool.stake(amount);
        stakeId = pool.nextStakeId() - 1;
    }

    function _notify(uint256 amount) internal {
        vm.prank(rewarder);
        pool.notifyReward(amount);
    }

    function _claim(address who, uint256 stakeId) internal {
        vm.prank(who);
        pool.claim(stakeId);
    }

    function _unstake(address who, uint256 stakeId) internal {
        vm.prank(who);
        pool.unstake(stakeId);
    }

    function _activateLpMode() internal {
        vm.prank(lpActivatorAddr);
        pool.activateLpMode(address(lp));
    }

    /// @dev Mints USDT and approves pool for LP staking. Call before addLiquidityAndStake.
    function _prepareForLp(address who, uint256 usdtAmount) internal {
        usdt.mint(who, usdtAmount);
        vm.prank(who);
        usdt.approve(address(pool), type(uint256).max);
        // arc already approved in setUp
    }

    function _addLpStake(address who, uint256 arcAmount, uint256 usdtAmount) internal returns (uint256 lpStakeId) {
        vm.prank(who);
        pool.addLiquidityAndStake(arcAmount, usdtAmount, 0, 0);
        lpStakeId = pool.nextLpStakeId() - 1;
    }
}

// ══════════════════════════════════════════════════════════════════════════════
// §1  Core correctness
// ══════════════════════════════════════════════════════════════════════════════

contract Test_CoreCorrectness is YieldPoolTest {
    // 1.1 ─ Single user: stake → reward → claim receives exact amount
    function test_SingleUser_FullReward() public {
        uint256 sid = _stake(alice, 100 * ARC_UNIT);
        _notify(1000 * USDT_UNIT);

        assertEq(pool.pendingReward(sid), 1000 * USDT_UNIT, "pending mismatch");

        uint256 before = usdt.balanceOf(alice);
        _claim(alice, sid);
        assertEq(usdt.balanceOf(alice) - before, 1000 * USDT_UNIT, "claim amount wrong");

        // Debt checkpoint prevents future double-claim
        assertEq(pool.pendingReward(sid), 0, "pending should be 0 after claim");
    }

    // 1.2 ─ Multi-user: proportional distribution (A=50%, B=30%, C=20%)
    function test_MultiUser_ProportionalDistribution() public {
        uint256 sidA = _stake(alice, 50 * ARC_UNIT);
        uint256 sidB = _stake(bob, 30 * ARC_UNIT);
        uint256 sidC = _stake(charlie, 20 * ARC_UNIT);

        _notify(1000 * USDT_UNIT);

        assertEq(pool.pendingReward(sidA), 500 * USDT_UNIT, "Alice share wrong");
        assertEq(pool.pendingReward(sidB), 300 * USDT_UNIT, "Bob share wrong");
        assertEq(pool.pendingReward(sidC), 200 * USDT_UNIT, "Charlie share wrong");

        uint256 total = pool.pendingReward(sidA) + pool.pendingReward(sidB) + pool.pendingReward(sidC);
        assertEq(total, 1000 * USDT_UNIT, "sum of rewards != injected");
    }

    // 1.3 ─ Sequential rewards accumulate without reset between deposits
    function test_SequentialRewards_Accumulate() public {
        uint256 sid = _stake(alice, 100 * ARC_UNIT);

        _notify(1000 * USDT_UNIT);
        _notify(1000 * USDT_UNIT);

        assertEq(pool.pendingReward(sid), 2000 * USDT_UNIT, "accumulated pending wrong");

        uint256 before = usdt.balanceOf(alice);
        _claim(alice, sid);
        assertEq(usdt.balanceOf(alice) - before, 2000 * USDT_UNIT, "claim after two rewards wrong");
    }
}

// ══════════════════════════════════════════════════════════════════════════════
// §2  RewardDebt correctness
// ══════════════════════════════════════════════════════════════════════════════

contract Test_RewardDebt is YieldPoolTest {
    // 2.1 ─ Claiming twice without new reward gives zero on second attempt
    function test_NodoubleClaim() public {
        uint256 sid = _stake(alice, 100 * ARC_UNIT);
        _notify(1000 * USDT_UNIT);
        _claim(alice, sid);

        vm.prank(alice);
        vm.expectRevert(YieldPoolErrors.NoRewardToClaim.selector);
        pool.claim(sid);
    }

    // 2.2 ─ Claim → new reward → claim again: each reward paid exactly once
    function test_PartialClaim_ThenNewReward() public {
        uint256 sid = _stake(alice, 100 * ARC_UNIT);

        _notify(1000 * USDT_UNIT);
        uint256 before1 = usdt.balanceOf(alice);
        _claim(alice, sid);
        assertEq(usdt.balanceOf(alice) - before1, 1000 * USDT_UNIT, "first claim wrong");

        _notify(1000 * USDT_UNIT);
        uint256 before2 = usdt.balanceOf(alice);
        _claim(alice, sid);
        assertEq(usdt.balanceOf(alice) - before2, 1000 * USDT_UNIT, "second claim wrong");
    }
}

// ══════════════════════════════════════════════════════════════════════════════
// §3  Mid-entry user tests
// ══════════════════════════════════════════════════════════════════════════════

contract Test_MidEntry is YieldPoolTest {
    // 3.1 ─ Late joiner earns nothing from rewards distributed before their stake
    function test_LateJoiner_NoPastRewards() public {
        uint256 sidA = _stake(alice, 50 * ARC_UNIT);

        _notify(1000 * USDT_UNIT);

        // Charlie joins after the reward was already distributed
        uint256 sidC = _stake(charlie, 50 * ARC_UNIT);

        assertEq(pool.pendingReward(sidC), 0, "late joiner should get 0 past reward");
        assertEq(pool.pendingReward(sidA), 1000 * USDT_UNIT, "early staker should get full reward");
    }

    // 3.2 ─ User joining immediately before reward only earns from that reward forward
    function test_JoinBeforeReward_EarnsOnlyFromThatPoint() public {
        uint256 sidA = _stake(alice, 50 * ARC_UNIT);
        // Charlie stakes in the same "moment" (same block) but before the reward
        uint256 sidC = _stake(charlie, 50 * ARC_UNIT);

        _notify(1000 * USDT_UNIT);

        // Both staked before the reward, so split evenly
        assertEq(pool.pendingReward(sidA), 500 * USDT_UNIT, "alice share wrong");
        assertEq(pool.pendingReward(sidC), 500 * USDT_UNIT, "charlie share wrong");

        // A second reward after Charlie is already in the pool
        _notify(1000 * USDT_UNIT);
        assertEq(pool.pendingReward(sidA), 1000 * USDT_UNIT, "alice accumulated wrong");
        assertEq(pool.pendingReward(sidC), 1000 * USDT_UNIT, "charlie accumulated wrong");
    }

    // 3.3 ─ rewardDebt correctly initialised for a late joiner
    function test_RewardDebt_InitialisedCorrectly() public {
        _stake(alice, 100 * ARC_UNIT);
        _notify(1000 * USDT_UNIT);

        uint256 sidC = _stake(charlie, 100 * ARC_UNIT);

        // Verify rewardDebt was initialised to the current accumulator snapshot
        (, uint256 rewardDebt,, bool active) = pool.stakes(sidC);
        uint256 expectedDebt = 100 * ARC_UNIT * pool.accRewardPerShare() / PRECISION;
        assertEq(rewardDebt, expectedDebt, "rewardDebt not initialised to current acc");
        assertTrue(active, "stake not active");
        assertEq(pool.pendingReward(sidC), 0, "pending must be 0 right after stake");
    }
}

// ══════════════════════════════════════════════════════════════════════════════
// §4  totalStaked manipulation
// ══════════════════════════════════════════════════════════════════════════════

contract Test_TotalStaked is YieldPoolTest {
    // 4.1 ─ New staker joining after reward does not dilute past reward recipients
    function test_NewStake_MidCycle_DoesNotDilutePast() public {
        uint256 sidA = _stake(alice, 50 * ARC_UNIT);
        uint256 sidB = _stake(bob, 50 * ARC_UNIT);

        _notify(1000 * USDT_UNIT);

        // Dave joins after the reward
        uint256 sidD = _stake(dave, 1_000 * ARC_UNIT);

        // Past rewards untouched
        assertEq(pool.pendingReward(sidA), 500 * USDT_UNIT, "alice past reward diluted");
        assertEq(pool.pendingReward(sidB), 500 * USDT_UNIT, "bob past reward diluted");
        assertEq(pool.pendingReward(sidD), 0, "dave should have no past reward");

        // Future reward split according to new weights (A=50, B=50, D=1000 → ~4.5%, 4.5%, 90.9%)
        _notify(1100 * USDT_UNIT);
        assertApproxEqAbs(pool.pendingReward(sidD), 1000 * USDT_UNIT, 1, "dave future reward wrong");
        assertApproxEqAbs(pool.pendingReward(sidA), 500 * USDT_UNIT + 50 * USDT_UNIT, 1, "alice total wrong");
        assertApproxEqAbs(pool.pendingReward(sidB), 500 * USDT_UNIT + 50 * USDT_UNIT, 1, "bob total wrong");
    }

    // 4.2 ─ Unstaking stops future reward accrual
    function test_Unstake_StopsAccrual() public {
        uint256 sidA = _stake(alice, 100 * ARC_UNIT);

        _notify(1000 * USDT_UNIT);

        // Alice unstakes; should receive her ARC + USDT reward atomically
        uint256 arcBefore = arc.balanceOf(alice);
        uint256 usdtBefore = usdt.balanceOf(alice);
        _unstake(alice, sidA);
        assertEq(arc.balanceOf(alice) - arcBefore, 100 * ARC_UNIT, "ARC not returned");
        assertEq(usdt.balanceOf(alice) - usdtBefore, 1000 * USDT_UNIT, "reward not paid on unstake");

        // Second reward injected — Alice must not receive it
        _notify(1000 * USDT_UNIT);
        assertEq(pool.pendingReward(sidA), 0, "unstaked position still accrues");
    }
}

// ══════════════════════════════════════════════════════════════════════════════
// §5  Zero-staker edge cases
// ══════════════════════════════════════════════════════════════════════════════

contract Test_ZeroStaker is YieldPoolTest {
    // 5.1 ─ Reward deposited with no stakers goes to queuedRewards, not lost
    function test_RewardWithNoStakers_Queued() public {
        _notify(1000 * USDT_UNIT);

        assertEq(pool.queuedRewards(), 1000 * USDT_UNIT, "reward not queued");
        assertEq(pool.accRewardPerShare(), 0, "acc should remain 0");
    }

    // 5.2 ─ Queued rewards distributed to stakers on next notifyReward
    function test_QueuedRewards_DistributedOnNextNotify() public {
        _notify(1000 * USDT_UNIT); // queued (no stakers)

        uint256 sid = _stake(alice, 100 * ARC_UNIT);

        // At this point queuedRewards is still 1000; alice's rewardDebt = 0 (acc still 0)
        assertEq(pool.pendingReward(sid), 0, "queued reward must not leak to new staker yet");

        _notify(500 * USDT_UNIT); // flushes queued + new = 1500 to alice

        assertEq(pool.pendingReward(sid), 1500 * USDT_UNIT, "flushed queued + new reward wrong");
        assertEq(pool.queuedRewards(), 0, "queuedRewards not cleared");
    }

    // 5.3 ─ Multiple queued deposits accumulate and flush together
    function test_MultipleQueuedDeposits_FlushTogether() public {
        _notify(500 * USDT_UNIT);
        _notify(500 * USDT_UNIT);

        assertEq(pool.queuedRewards(), 1000 * USDT_UNIT, "should have 1000 queued");

        uint256 sid = _stake(alice, 100 * ARC_UNIT);
        _notify(100 * USDT_UNIT);

        assertEq(pool.pendingReward(sid), 1100 * USDT_UNIT, "total flush wrong");
    }

    // 5.6 ─ No division-by-zero when reward is sent while totalStaked == 0
    function test_NoRevertOnZeroStake_Notify() public {
        _notify(1000 * USDT_UNIT);
        // must not revert
    }
}

// ══════════════════════════════════════════════════════════════════════════════
// §6  Precision & rounding
// ══════════════════════════════════════════════════════════════════════════════

contract Test_Precision is YieldPoolTest {
    // 6.1 ─ Tiny reward across many stakers: sum of payouts <= reward (rounding down only)
    function test_SmallReward_RoundingDirection() public {
        uint256 sidA = _stake(alice, 33 * ARC_UNIT);
        uint256 sidB = _stake(bob, 33 * ARC_UNIT);
        uint256 sidC = _stake(charlie, 34 * ARC_UNIT);

        _notify(100 * USDT_UNIT);

        uint256 sumPending = pool.pendingReward(sidA) + pool.pendingReward(sidB) + pool.pendingReward(sidC);

        // Rounding must always round DOWN, so sum <= injected; delta should be at most a few wei
        assertLe(sumPending, 100 * USDT_UNIT, "sum of rewards exceeds injected (impossible with floor division)");
        assertApproxEqAbs(sumPending, 100 * USDT_UNIT, 3, "too much dust lost");
    }

    // 6.2 ─ Large stake amounts: no overflow
    function test_LargeAmounts_NoOverflow() public {
        // Max reasonable amounts: 100B ARC staked, 10M USDT reward
        arc.mint(alice, 100_000_000_000 * ARC_UNIT);
        vm.prank(alice);
        arc.approve(address(pool), type(uint256).max);

        uint256 sid = _stake(alice, 100_000_000_000 * ARC_UNIT);
        _notify(10_000_000 * USDT_UNIT);

        // Should not overflow; pending should equal the reward exactly (single staker)
        assertEq(pool.pendingReward(sid), 10_000_000 * USDT_UNIT, "large amount calculation wrong");
    }

    // 6.3 ─ accRewardPerShare monotonically increases across multiple notifications
    function test_AccRewardPerShare_Monotonic() public {
        _stake(alice, 100 * ARC_UNIT);

        uint256 prev = pool.accRewardPerShare();
        for (uint256 i; i < 10; ++i) {
            _notify(100 * USDT_UNIT);
            uint256 curr = pool.accRewardPerShare();
            assertGt(curr, prev, "accRewardPerShare decreased");
            prev = curr;
        }
    }
}

// ══════════════════════════════════════════════════════════════════════════════
// §7  Multiple stake positions per user
// ══════════════════════════════════════════════════════════════════════════════

contract Test_MultipleStakes is YieldPoolTest {
    // 7.1 ─ Independent positions accumulate rewards separately
    function test_TwoPositions_IndependentAccrual() public {
        uint256 sid1 = _stake(alice, 50 * ARC_UNIT);
        uint256 sid2 = _stake(alice, 100 * ARC_UNIT);

        _notify(1500 * USDT_UNIT);

        // sid1 holds 50/150 = 1/3, sid2 holds 100/150 = 2/3
        assertEq(pool.pendingReward(sid1), 500 * USDT_UNIT, "position 1 reward wrong");
        assertEq(pool.pendingReward(sid2), 1000 * USDT_UNIT, "position 2 reward wrong");
    }

    // 7.2 ─ Claiming one position does not contaminate the other
    function test_ClaimOnePosition_OtherUnaffected() public {
        uint256 sid1 = _stake(alice, 50 * ARC_UNIT);
        uint256 sid2 = _stake(alice, 100 * ARC_UNIT);

        _notify(1500 * USDT_UNIT);

        _claim(alice, sid1);

        // sid2 pending unchanged
        assertEq(pool.pendingReward(sid2), 1000 * USDT_UNIT, "other position contaminated");
        // sid1 is now zero
        assertEq(pool.pendingReward(sid1), 0, "claimed position still shows pending");
    }

    // 7.3 ─ batchClaim collects all positions in one transfer
    function test_BatchClaim_AllPositions() public {
        uint256 sid1 = _stake(alice, 50 * ARC_UNIT);
        uint256 sid2 = _stake(alice, 100 * ARC_UNIT);

        _notify(1500 * USDT_UNIT);

        uint256 before = usdt.balanceOf(alice);
        uint256[] memory ids = new uint256[](2);
        ids[0] = sid1;
        ids[1] = sid2;
        vm.prank(alice);
        pool.batchClaim(ids);

        assertEq(usdt.balanceOf(alice) - before, 1500 * USDT_UNIT, "batchClaim total wrong");
        assertEq(pool.pendingReward(sid1), 0, "sid1 not settled");
        assertEq(pool.pendingReward(sid2), 0, "sid2 not settled");
    }

    // 7.4 ─ batchClaim with duplicate stakeId does not double-pay
    function test_BatchClaim_DuplicateId_NoDoublePay() public {
        uint256 sid = _stake(alice, 100 * ARC_UNIT);
        _notify(1000 * USDT_UNIT);

        uint256 before = usdt.balanceOf(alice);
        uint256[] memory ids = new uint256[](2);
        ids[0] = sid;
        ids[1] = sid; // duplicate
        vm.prank(alice);
        pool.batchClaim(ids);

        // Second settle computes 0; only one transfer happens
        assertEq(usdt.balanceOf(alice) - before, 1000 * USDT_UNIT, "duplicate stakeId paid twice");
    }

    // 7.5 ─ getUserStakeIds returns all IDs including inactive ones
    function test_GetUserStakeIds_IncludesInactive() public {
        uint256 sid1 = _stake(alice, 50 * ARC_UNIT);
        uint256 sid2 = _stake(alice, 50 * ARC_UNIT);
        _notify(1000 * USDT_UNIT);
        _unstake(alice, sid1);

        uint256[] memory ids = pool.getUserStakeIds(alice);
        assertEq(ids.length, 2, "should return both IDs");
        assertEq(ids[0], sid1, "id[0] wrong");
        assertEq(ids[1], sid2, "id[1] wrong");
    }
}

// ══════════════════════════════════════════════════════════════════════════════
// §8  Claim timing
// ══════════════════════════════════════════════════════════════════════════════

contract Test_ClaimTiming is YieldPoolTest {
    // 8.1 ─ Reward injected between view-pending and actual claim is captured
    function test_NewReward_BetweenViewAndClaim() public {
        uint256 sid = _stake(alice, 100 * ARC_UNIT);
        _notify(1000 * USDT_UNIT);

        // Simulates: off-chain sees pending = 1000, then a new reward lands
        _notify(500 * USDT_UNIT);

        uint256 before = usdt.balanceOf(alice);
        _claim(alice, sid);
        // Claim should reflect the updated state, not the stale view
        assertEq(usdt.balanceOf(alice) - before, 1500 * USDT_UNIT, "stale pending used instead of latest");
    }
}

// ══════════════════════════════════════════════════════════════════════════════
// §9  Attack-style tests
// ══════════════════════════════════════════════════════════════════════════════

contract Test_Attacks is YieldPoolTest {
    // 9.1 ─ Direct USDT donation does not manipulate accRewardPerShare
    function test_DirectDonation_CannotManipulateAcc() public {
        uint256 sid = _stake(alice, 100 * ARC_UNIT);
        _notify(1000 * USDT_UNIT);

        uint256 accBefore = pool.accRewardPerShare();

        // Attacker donates USDT directly (no approval to pool for notifyReward path)
        usdt.mint(attacker, 1_000_000 * USDT_UNIT);
        vm.prank(attacker);
        require(usdt.transfer(address(pool), 1_000_000 * USDT_UNIT), "transfer failed");

        assertEq(pool.accRewardPerShare(), accBefore, "direct donation changed accumulator");
        assertEq(pool.pendingReward(sid), 1000 * USDT_UNIT, "alice's reward changed by donation");
    }

    // 9.2 ─ Large late staker does not dilute existing stakers' past rewards
    function test_LateInflationAttack_DoesNotDilutePast() public {
        uint256 sidA = _stake(alice, 100 * ARC_UNIT);
        _notify(1000 * USDT_UNIT);

        // Attacker stakes a huge amount after the reward
        uint256 sidAtt = _stake(attacker, 1_000_000 * ARC_UNIT);

        // Alice's pending must remain exactly 1000
        assertEq(pool.pendingReward(sidA), 1000 * USDT_UNIT, "alice reward diluted by late attacker");
        assertEq(pool.pendingReward(sidAtt), 0, "attacker should have zero past reward");
    }

    // 9.3 ─ Flash stake: stake → reward → unstake in same block; reward is proportional, not stolen
    function test_FlashStake_ProportionalNotFree() public {
        _stake(alice, 100 * ARC_UNIT); // totalStaked = 100

        // Attacker stakes 100 (now 50/50) then reward then unstake — all same block
        uint256 sidAtt = _stake(attacker, 100 * ARC_UNIT); // totalStaked = 200

        _notify(1000 * USDT_UNIT); // split 50/50

        uint256 usdtBefore = usdt.balanceOf(attacker);
        uint256 arcBefore = arc.balanceOf(attacker);
        _unstake(attacker, sidAtt);

        // Attacker gets 500 USDT (their proportional share) — not 0, not all of it
        assertEq(usdt.balanceOf(attacker) - usdtBefore, 500 * USDT_UNIT, "flash stake reward wrong");
        assertEq(arc.balanceOf(attacker) - arcBefore, 100 * ARC_UNIT, "ARC not returned to attacker");
    }

    // 9.4 ─ Access: random caller cannot call notifyReward
    function test_AccessControl_NotifyReward_Restricted() public {
        vm.prank(attacker);
        vm.expectRevert(YieldPoolErrors.NotRewarder.selector);
        pool.notifyReward(1000 * USDT_UNIT);
    }

    // 9.7 ─ Ownership: non-owner cannot unstake another user's position
    function test_Ownership_CannotUnstakeOthers() public {
        uint256 sid = _stake(alice, 100 * ARC_UNIT);
        vm.prank(attacker);
        vm.expectRevert(YieldPoolErrors.NotStakeOwner.selector);
        pool.unstake(sid);
    }

    // 9.8 ─ Ownership: non-owner cannot claim another user's rewards
    function test_Ownership_CannotClaimOthers() public {
        uint256 sid = _stake(alice, 100 * ARC_UNIT);
        _notify(1000 * USDT_UNIT);
        vm.prank(attacker);
        vm.expectRevert(YieldPoolErrors.NotStakeOwner.selector);
        pool.claim(sid);
    }
}

// ══════════════════════════════════════════════════════════════════════════════
// §10  Invariant / fuzz tests
// ══════════════════════════════════════════════════════════════════════════════

contract Test_Invariants is YieldPoolTest {
    // 10.1 ─ Fuzz: single staker always receives exactly what was injected
    function testFuzz_SingleStaker_GetsFullReward(uint256 amount, uint256 stakeAmt) public {
        amount = bound(amount, 1 * USDT_UNIT, 1_000_000 * USDT_UNIT);
        stakeAmt = bound(stakeAmt, 1 * ARC_UNIT, 100_000 * ARC_UNIT);

        arc.mint(alice, stakeAmt);
        vm.prank(alice);
        arc.approve(address(pool), stakeAmt);
        usdt.mint(rewarder, amount);
        vm.prank(rewarder);
        usdt.approve(address(pool), amount);

        uint256 sid = _stake(alice, stakeAmt);
        _notify(amount);

        // Floor division in accRewardPerShare can truncate at most 1 unit per distribution.
        assertApproxEqAbs(pool.pendingReward(sid), amount, 1, "single staker should get full reward");
    }

    // 10.2 ─ Fuzz: sum of two stakers' rewards == injected reward (no creation/destruction)
    function testFuzz_TwoStakers_SumEqualsInjected(uint256 stakeA, uint256 stakeB, uint256 reward) public {
        stakeA = bound(stakeA, 1 * ARC_UNIT, 500_000 * ARC_UNIT);
        stakeB = bound(stakeB, 1 * ARC_UNIT, 500_000 * ARC_UNIT);
        reward = bound(reward, 1 * USDT_UNIT, 1_000_000 * USDT_UNIT);

        usdt.mint(rewarder, reward);
        vm.prank(rewarder);
        usdt.approve(address(pool), reward);

        uint256 sidA = _stake(alice, stakeA);
        uint256 sidB = _stake(bob, stakeB);
        _notify(reward);

        uint256 pendA = pool.pendingReward(sidA);
        uint256 pendB = pool.pendingReward(sidB);

        // Each staker's pending floors independently; max combined loss = 2 (one per staker).
        assertLe(pendA + pendB, reward, "sum exceeds reward (impossible)");
        assertApproxEqAbs(pendA + pendB, reward, 2, "too much rounding loss");
    }

    // 10.3 ─ Fuzz: pending is never negative (would revert on underflow in Solidity ≥0.8)
    function testFuzz_PendingNeverNegative(uint256 reward1, uint256 reward2, uint256 stakeAmt) public {
        stakeAmt = bound(stakeAmt, 1 * ARC_UNIT, 100_000 * ARC_UNIT);
        reward1 = bound(reward1, 1 * USDT_UNIT, 500_000 * USDT_UNIT);
        reward2 = bound(reward2, 1 * USDT_UNIT, 500_000 * USDT_UNIT);

        usdt.mint(rewarder, reward1 + reward2);
        vm.prank(rewarder);
        usdt.approve(address(pool), reward1 + reward2);

        uint256 sid = _stake(alice, stakeAmt);
        _notify(reward1);
        _claim(alice, sid);
        _notify(reward2);

        // pendingReward() must not revert; result must be >= 0
        uint256 pending = pool.pendingReward(sid);
        assertGe(pending, 0, "pending is negative (impossible in uint)");
    }

    // 10.4 ─ Fuzz: accRewardPerShare monotonically increases
    function testFuzz_AccRewardPerShare_Monotonic(uint256[5] memory rewards) public {
        _stake(alice, 100 * ARC_UNIT);

        uint256 prev = pool.accRewardPerShare();
        for (uint256 i; i < 5; ++i) {
            uint256 r = bound(rewards[i], 1 * USDT_UNIT, 100_000 * USDT_UNIT);
            usdt.mint(rewarder, r);
            vm.prank(rewarder);
            usdt.approve(address(pool), r);
            _notify(r);

            uint256 curr = pool.accRewardPerShare();
            assertGe(curr, prev, "accRewardPerShare decreased");
            prev = curr;
        }
    }

    // 10.5 ─ Fuzz: contract USDT balance always covers all pending + claimable
    function testFuzz_ContractBalance_CoversAllPending(uint256 stakeA, uint256 stakeB, uint256 reward) public {
        stakeA = bound(stakeA, 1 * ARC_UNIT, 500_000 * ARC_UNIT);
        stakeB = bound(stakeB, 1 * ARC_UNIT, 500_000 * ARC_UNIT);
        reward = bound(reward, 2 * USDT_UNIT, 1_000_000 * USDT_UNIT);

        usdt.mint(rewarder, reward);
        vm.prank(rewarder);
        usdt.approve(address(pool), reward);

        uint256 sidA = _stake(alice, stakeA);
        uint256 sidB = _stake(bob, stakeB);
        _notify(reward);

        uint256 poolBalance = usdt.balanceOf(address(pool));
        uint256 totalPending = pool.pendingReward(sidA) + pool.pendingReward(sidB);

        assertGe(poolBalance, totalPending, "pool cannot cover all pending rewards");
    }
}

// ══════════════════════════════════════════════════════════════════════════════
// §11  Full lifecycle integration
// ══════════════════════════════════════════════════════════════════════════════

contract Test_FullLifecycle is YieldPoolTest {
    function test_FullLifecycle() public {
        // Step 1: A, B, C stake
        uint256 sidA = _stake(alice, 50 * ARC_UNIT);
        uint256 sidB = _stake(bob, 30 * ARC_UNIT);
        uint256 sidC = _stake(charlie, 20 * ARC_UNIT);
        // totalStaked = 100

        // Step 2: reward1 = 1000 USDT injected
        _notify(1000 * USDT_UNIT);
        // A = 500, B = 300, C = 200

        assertEq(pool.pendingReward(sidA), 500 * USDT_UNIT);
        assertEq(pool.pendingReward(sidB), 300 * USDT_UNIT);
        assertEq(pool.pendingReward(sidC), 200 * USDT_UNIT);

        // Step 3: A claims
        uint256 aliceBefore = usdt.balanceOf(alice);
        _claim(alice, sidA);
        assertEq(usdt.balanceOf(alice) - aliceBefore, 500 * USDT_UNIT);
        assertEq(pool.pendingReward(sidA), 0);

        // Step 4: C does NOT claim (holds 200 pending)

        // Step 5: D joins after reward1
        uint256 sidD = _stake(dave, 100 * ARC_UNIT);
        assertEq(pool.pendingReward(sidD), 0, "D should have no past reward");
        // totalStaked = 200

        // Step 6: reward2 = 1000 USDT injected
        // Shares: A=50/200=25%, B=30/200=15%, C=20/200=10%, D=100/200=50%
        _notify(1000 * USDT_UNIT);

        assertEq(pool.pendingReward(sidA), 250 * USDT_UNIT, "A reward2 wrong");
        assertEq(pool.pendingReward(sidB), 300 * USDT_UNIT + 150 * USDT_UNIT, "B accumulated wrong");
        assertEq(pool.pendingReward(sidC), 200 * USDT_UNIT + 100 * USDT_UNIT, "C accumulated wrong");
        assertEq(pool.pendingReward(sidD), 500 * USDT_UNIT, "D reward2 wrong");

        // Step 7: all users claim
        uint256 bBefore = usdt.balanceOf(bob);
        uint256 cBefore = usdt.balanceOf(charlie);
        uint256 dBefore = usdt.balanceOf(dave);

        _claim(alice, sidA);
        _claim(bob, sidB);
        _claim(charlie, sidC);
        _claim(dave, sidD);

        assertEq(usdt.balanceOf(alice) - aliceBefore, 750 * USDT_UNIT, "Alice total wrong");
        assertEq(usdt.balanceOf(bob) - bBefore, 450 * USDT_UNIT, "Bob total wrong");
        assertEq(usdt.balanceOf(charlie) - cBefore, 300 * USDT_UNIT, "Charlie total wrong");
        assertEq(usdt.balanceOf(dave) - dBefore, 500 * USDT_UNIT, "Dave total wrong");

        // Conservation: 750+450+300+500 = 2000 = total injected
        assertEq(uint256(750 + 450 + 300 + 500), uint256(2000), "conservation broken");

        // Step 8: A exits (unstakes, no pending since just claimed)
        uint256 arcBefore = arc.balanceOf(alice);
        _unstake(alice, sidA);
        assertEq(arc.balanceOf(alice) - arcBefore, 50 * ARC_UNIT, "ARC not returned to alice");
        // totalStaked = 150

        // Step 9: reward3 = 1500 USDT (A no longer participates)
        // Shares: B=30/150=20%, C=20/150=13.3%, D=100/150=66.7%
        _notify(1500 * USDT_UNIT);

        assertEq(pool.pendingReward(sidA), 0, "exited A should earn nothing");
        assertEq(pool.pendingReward(sidB), 300 * USDT_UNIT, "B reward3 wrong");
        assertEq(pool.pendingReward(sidC), 200 * USDT_UNIT, "C reward3 wrong");
        assertEq(pool.pendingReward(sidD), 1000 * USDT_UNIT, "D reward3 wrong");

        // Step 10: remaining users claim
        bBefore = usdt.balanceOf(bob);
        cBefore = usdt.balanceOf(charlie);
        dBefore = usdt.balanceOf(dave);

        _claim(bob, sidB);
        _claim(charlie, sidC);
        _claim(dave, sidD);

        assertEq(usdt.balanceOf(bob) - bBefore, 300 * USDT_UNIT, "Bob reward3 claim wrong");
        assertEq(usdt.balanceOf(charlie) - cBefore, 200 * USDT_UNIT, "Charlie reward3 claim wrong");
        assertEq(usdt.balanceOf(dave) - dBefore, 1000 * USDT_UNIT, "Dave reward3 claim wrong");

        // Final conservation: 300+200+1000 = 1500 = reward3
        assertEq(uint256(300 + 200 + 1000), uint256(1500), "reward3 conservation broken");
    }
}

// ─── Freezable USDT mock (used only in §13) ───────────────────────────────────

contract MockFreezableUSDT is ERC20 {
    bool public transferReverts;
    bool public transferReturnsFalse;
    // When set, only transfers *from* this address are frozen (simulates address blacklisting).
    // When address(0) (default), ALL transfers are frozen (simulates global pause).
    address public frozenSender;

    constructor() ERC20("Tether USD", "USDT") {}

    function decimals() public pure override returns (uint8) {
        return 6;
    }

    function mint(address to, uint256 amount) external {
        _mint(to, amount);
    }

    function setTransferReverts(bool value) external {
        transferReverts = value;
    }

    function setTransferReturnsFalse(bool value) external {
        transferReturnsFalse = value;
    }

    function setFrozenSender(address who) external {
        frozenSender = who;
    }

    function transfer(address to, uint256 amount) public override returns (bool) {
        bool affectsThisSender = frozenSender == address(0) || msg.sender == frozenSender;
        if (affectsThisSender && transferReverts) revert("USDT: frozen");
        if (affectsThisSender && transferReturnsFalse) return false;
        return super.transfer(to, amount);
    }
}

// ══════════════════════════════════════════════════════════════════════════════
// §12  Error & constructor validation
// ══════════════════════════════════════════════════════════════════════════════

contract Test_ErrorsAndConstructor is YieldPoolTest {
    // Constructor rejects zero addresses for all five parameters
    function test_Constructor_ZeroAddress_Reverts() public {
        vm.expectRevert(YieldPoolErrors.ZeroAddress.selector);
        new YieldPool(address(0), address(usdt), rewarder, lpActivatorAddr, address(router));

        vm.expectRevert(YieldPoolErrors.ZeroAddress.selector);
        new YieldPool(address(arc), address(0), rewarder, lpActivatorAddr, address(router));

        vm.expectRevert(YieldPoolErrors.ZeroAddress.selector);
        new YieldPool(address(arc), address(usdt), address(0), lpActivatorAddr, address(router));

        vm.expectRevert(YieldPoolErrors.ZeroAddress.selector);
        new YieldPool(address(arc), address(usdt), rewarder, address(0), address(router));

        vm.expectRevert(YieldPoolErrors.ZeroAddress.selector);
        new YieldPool(address(arc), address(usdt), rewarder, lpActivatorAddr, address(0));
    }

    // Staking zero amount reverts
    function test_Stake_ZeroAmount_Reverts() public {
        vm.prank(alice);
        vm.expectRevert(YieldPoolErrors.ZeroAmount.selector);
        pool.stake(0);
    }

    // notifyReward zero amount reverts
    function test_NotifyReward_ZeroAmount_Reverts() public {
        vm.prank(rewarder);
        vm.expectRevert(YieldPoolErrors.ZeroAmount.selector);
        pool.notifyReward(0);
    }

    // Claiming inactive stake reverts
    function test_Claim_InactiveStake_Reverts() public {
        uint256 sid = _stake(alice, 100 * ARC_UNIT);
        _notify(1000 * USDT_UNIT);
        _unstake(alice, sid);

        vm.prank(alice);
        vm.expectRevert(YieldPoolErrors.StakeNotActive.selector);
        pool.claim(sid);
    }

    // Unstaking inactive stake reverts
    function test_Unstake_InactiveStake_Reverts() public {
        uint256 sid = _stake(alice, 100 * ARC_UNIT);
        _notify(1000 * USDT_UNIT);
        _unstake(alice, sid);

        vm.prank(alice);
        vm.expectRevert(YieldPoolErrors.StakeNotActive.selector);
        pool.unstake(sid);
    }

    // batchClaim with empty array reverts
    function test_BatchClaim_EmptyArray_Reverts() public {
        vm.prank(alice);
        vm.expectRevert(YieldPoolErrors.EmptyStakeIds.selector);
        pool.batchClaim(new uint256[](0));
    }
}

// ══════════════════════════════════════════════════════════════════════════════
// §13  Frozen rewards — USDT paused/blacklisted during unstake
// ══════════════════════════════════════════════════════════════════════════════

contract Test_FrozenRewards is Test {
    uint256 internal constant ARC_UNIT = 1e18;
    uint256 internal constant USDT_UNIT = 1e6;

    YieldPool internal pool;
    MockARC internal arc;
    MockFreezableUSDT internal usdt;

    address internal alice = makeAddr("alice");
    address internal bob = makeAddr("bob");
    address internal rewarder = makeAddr("rewarder");
    address internal lpActivatorAddr = makeAddr("lpActivator");

    function setUp() public {
        arc = new MockARC();
        usdt = new MockFreezableUSDT();
        MockLP lp = new MockLP();
        MockUniswapV2Router router = new MockUniswapV2Router(address(lp));
        pool = new YieldPool(address(arc), address(usdt), rewarder, lpActivatorAddr, address(router));

        arc.mint(alice, 1_000_000 * ARC_UNIT);
        arc.mint(bob, 1_000_000 * ARC_UNIT);
        usdt.mint(rewarder, 10_000_000 * USDT_UNIT);

        vm.prank(alice);
        arc.approve(address(pool), type(uint256).max);
        vm.prank(bob);
        arc.approve(address(pool), type(uint256).max);
        vm.prank(rewarder);
        usdt.approve(address(pool), type(uint256).max);
    }

    function _stake(address who, uint256 amount) internal returns (uint256 stakeId) {
        vm.prank(who);
        pool.stake(amount);
        stakeId = pool.nextStakeId() - 1;
    }

    function _notify(uint256 amount) internal {
        vm.prank(rewarder);
        pool.notifyReward(amount);
    }

    function _unstake(address who, uint256 stakeId) internal {
        vm.prank(who);
        pool.unstake(stakeId);
    }

    // 13.1 — USDT transfer reverts: ARC returned, reward frozen, RewardFrozen emitted
    function test_Unstake_UsdtReverts_ArcReturnedRewardFrozen() public {
        uint256 sid = _stake(alice, 100 * ARC_UNIT);
        _notify(1000 * USDT_UNIT);

        usdt.setTransferReverts(true);

        uint256 arcBefore = arc.balanceOf(alice);
        vm.expectEmit(true, true, false, true);
        emit YieldPoolEvents.RewardFrozen(alice, sid, 1000 * USDT_UNIT);
        _unstake(alice, sid);

        assertEq(arc.balanceOf(alice) - arcBefore, 100 * ARC_UNIT, "ARC not returned");
        assertEq(pool.frozenRewards(alice), 1000 * USDT_UNIT, "frozen reward not tracked");
        assertEq(usdt.balanceOf(alice), 0, "USDT must not have transferred");
    }

    // 13.2 — USDT returns false: ARC returned, reward frozen
    function test_Unstake_UsdtReturnsFalse_ArcReturnedRewardFrozen() public {
        uint256 sid = _stake(alice, 100 * ARC_UNIT);
        _notify(1000 * USDT_UNIT);

        usdt.setTransferReturnsFalse(true);

        uint256 arcBefore = arc.balanceOf(alice);
        _unstake(alice, sid);

        assertEq(arc.balanceOf(alice) - arcBefore, 100 * ARC_UNIT, "ARC not returned");
        assertEq(pool.frozenRewards(alice), 1000 * USDT_UNIT, "frozen reward not tracked");
        assertEq(usdt.balanceOf(alice), 0, "USDT must not have transferred");
    }

    // 13.3 — claimFrozenRewards with no frozen balance reverts with NoFrozenRewards
    function test_ClaimFrozenRewards_NoBalance_Reverts() public {
        vm.prank(alice);
        vm.expectRevert(YieldPoolErrors.NoFrozenRewards.selector);
        pool.claimFrozenRewards();
    }

    // 13.4 — Successful claim after USDT is unpaused; balance cleared
    function test_ClaimFrozenRewards_AfterUnfreeze() public {
        uint256 sid = _stake(alice, 100 * ARC_UNIT);
        _notify(1000 * USDT_UNIT);

        usdt.setTransferReverts(true);
        _unstake(alice, sid);
        assertEq(pool.frozenRewards(alice), 1000 * USDT_UNIT);

        usdt.setTransferReverts(false);

        uint256 before = usdt.balanceOf(alice);
        vm.prank(alice);
        pool.claimFrozenRewards();

        assertEq(usdt.balanceOf(alice) - before, 1000 * USDT_UNIT, "frozen reward not paid out");
        assertEq(pool.frozenRewards(alice), 0, "frozen balance not cleared");
    }

    // 13.5 — Calling claimFrozenRewards twice reverts on second call (no double-claim)
    function test_ClaimFrozenRewards_NoDoubleClaim() public {
        uint256 sid = _stake(alice, 100 * ARC_UNIT);
        _notify(1000 * USDT_UNIT);

        usdt.setTransferReverts(true);
        _unstake(alice, sid);
        usdt.setTransferReverts(false);

        vm.prank(alice);
        pool.claimFrozenRewards();

        vm.prank(alice);
        vm.expectRevert(YieldPoolErrors.NoFrozenRewards.selector);
        pool.claimFrozenRewards();
    }

    // 13.6 — Multiple unstakes while frozen accumulate into frozenRewards
    function test_MultipleUnstakes_FrozenRewardsAccumulate() public {
        uint256 sid1 = _stake(alice, 100 * ARC_UNIT); // totalStaked = 100
        _notify(1000 * USDT_UNIT); // alice earns 1000
        uint256 sid2 = _stake(alice, 100 * ARC_UNIT); // totalStaked = 200
        _notify(1000 * USDT_UNIT); // sid1 earns 500, sid2 earns 500

        // sid1 pending = 1000 + 500 = 1500; sid2 pending = 500
        usdt.setTransferReverts(true);
        _unstake(alice, sid1);
        _unstake(alice, sid2);

        assertEq(pool.frozenRewards(alice), 2000 * USDT_UNIT, "accumulated frozen rewards wrong");
    }

    // 13.7 — Unstake with zero pending reward: no frozen entry, ARC returned normally
    function test_Unstake_ZeroReward_NoFrozenEntry() public {
        uint256 sid = _stake(alice, 100 * ARC_UNIT);
        // No notifyReward — reward = 0

        usdt.setTransferReverts(true);

        uint256 arcBefore = arc.balanceOf(alice);
        _unstake(alice, sid);

        assertEq(arc.balanceOf(alice) - arcBefore, 100 * ARC_UNIT, "ARC not returned");
        assertEq(pool.frozenRewards(alice), 0, "no frozen entry expected for zero reward");
    }

    // 13.8 — Frozen rewards are per-user; one user's freeze does not affect another
    function test_FrozenRewards_PerUser_Isolated() public {
        uint256 sidA = _stake(alice, 100 * ARC_UNIT);
        uint256 sidB = _stake(bob, 100 * ARC_UNIT);
        _notify(2000 * USDT_UNIT); // each earns 1000

        usdt.setTransferReverts(true);
        _unstake(alice, sidA);

        usdt.setTransferReverts(false);
        uint256 bobBefore = usdt.balanceOf(bob);
        _unstake(bob, sidB);

        assertEq(pool.frozenRewards(alice), 1000 * USDT_UNIT, "alice frozen wrong");
        assertEq(pool.frozenRewards(bob), 0, "bob should have no frozen rewards");
        assertEq(usdt.balanceOf(bob) - bobBefore, 1000 * USDT_UNIT, "bob payout wrong");
    }
}

// ══════════════════════════════════════════════════════════════════════════════
// §14  batchUnstake
// ══════════════════════════════════════════════════════════════════════════════

contract Test_BatchUnstake is YieldPoolTest {
    // 14.1 — Empty array reverts
    function test_BatchUnstake_EmptyArray_Reverts() public {
        vm.prank(alice);
        vm.expectRevert(YieldPoolErrors.EmptyStakeIds.selector);
        pool.batchUnstake(new uint256[](0));
    }

    // 14.1b — Array longer than 20 reverts with BatchTooLarge
    function test_BatchUnstake_TooLarge_Reverts() public {
        vm.prank(alice);
        vm.expectRevert(YieldPoolErrors.BatchTooLarge.selector);
        pool.batchUnstake(new uint256[](21));
    }

    // 14.1c — Exactly 20 positions is accepted (boundary)
    function test_BatchUnstake_ExactlyMaxLen_Accepted() public {
        uint256[] memory ids = new uint256[](20);
        for (uint256 i; i < 20; ++i) {
            ids[i] = _stake(alice, ARC_UNIT);
        }
        _notify(2000 * USDT_UNIT);

        uint256 arcBefore = arc.balanceOf(alice);
        vm.prank(alice);
        pool.batchUnstake(ids); // must not revert

        assertEq(arc.balanceOf(alice) - arcBefore, 20 * ARC_UNIT, "ARC not returned for 20 positions");
    }

    // 14.2 — Inactive stakeId reverts (no partial commit)
    function test_BatchUnstake_InactiveStake_Reverts() public {
        uint256 sid1 = _stake(alice, 100 * ARC_UNIT);
        uint256 sid2 = _stake(alice, 100 * ARC_UNIT);
        _notify(1000 * USDT_UNIT);
        _unstake(alice, sid1); // now inactive

        uint256[] memory ids = new uint256[](2);
        ids[0] = sid2;
        ids[1] = sid1; // inactive — should revert
        vm.prank(alice);
        vm.expectRevert(YieldPoolErrors.StakeNotActive.selector);
        pool.batchUnstake(ids);

        // sid2 must still be active (no partial commit)
        (,,, bool active) = pool.stakes(sid2);
        assertTrue(active, "sid2 must remain active after revert");
    }

    // 14.3 — Non-owner stakeId reverts
    function test_BatchUnstake_NotOwner_Reverts() public {
        uint256 sidAlice = _stake(alice, 100 * ARC_UNIT);
        uint256 sidBob = _stake(bob, 100 * ARC_UNIT);

        uint256[] memory ids = new uint256[](2);
        ids[0] = sidAlice;
        ids[1] = sidBob; // bob's — alice cannot unstake
        vm.prank(alice);
        vm.expectRevert(YieldPoolErrors.NotStakeOwner.selector);
        pool.batchUnstake(ids);
    }

    // 14.4 — Full batch: ARC returned, USDT paid, all positions closed
    function test_BatchUnstake_FullBatch_ArcAndUsdtReturned() public {
        uint256 sid1 = _stake(alice, 50 * ARC_UNIT);
        uint256 sid2 = _stake(alice, 100 * ARC_UNIT);
        uint256 sid3 = _stake(alice, 150 * ARC_UNIT);
        _notify(3000 * USDT_UNIT); // split 50/300, 100/300, 150/300

        uint256 arcBefore = arc.balanceOf(alice);
        uint256 usdtBefore = usdt.balanceOf(alice);

        uint256[] memory ids = new uint256[](3);
        ids[0] = sid1;
        ids[1] = sid2;
        ids[2] = sid3;
        vm.prank(alice);
        pool.batchUnstake(ids);

        assertEq(arc.balanceOf(alice) - arcBefore, 300 * ARC_UNIT, "total ARC wrong");
        assertEq(usdt.balanceOf(alice) - usdtBefore, 3000 * USDT_UNIT, "total USDT wrong");

        (,,, bool a1) = pool.stakes(sid1);
        (,,, bool a2) = pool.stakes(sid2);
        (,,, bool a3) = pool.stakes(sid3);
        assertFalse(a1);
        assertFalse(a2);
        assertFalse(a3);
    }

    // 14.5 — totalStaked is reduced correctly across all positions
    function test_BatchUnstake_TotalStaked_ReducedCorrectly() public {
        _stake(alice, 60 * ARC_UNIT);
        uint256 sid2 = _stake(alice, 40 * ARC_UNIT);
        _stake(bob, 100 * ARC_UNIT);
        assertEq(pool.totalStaked(), 200 * ARC_UNIT);

        uint256[] memory ids = new uint256[](1);
        ids[0] = sid2;
        vm.prank(alice);
        pool.batchUnstake(ids);

        assertEq(pool.totalStaked(), 160 * ARC_UNIT, "totalStaked not decremented");
    }

    // 14.6 — batchUnstake with no accrued reward: only ARC transferred, no USDT call
    function test_BatchUnstake_NoReward_OnlyArcReturned() public {
        uint256 sid1 = _stake(alice, 50 * ARC_UNIT);
        uint256 sid2 = _stake(alice, 50 * ARC_UNIT);
        // no notifyReward — totalReward == 0

        uint256 arcBefore = arc.balanceOf(alice);
        uint256 usdtBefore = usdt.balanceOf(alice);

        uint256[] memory ids = new uint256[](2);
        ids[0] = sid1;
        ids[1] = sid2;
        vm.prank(alice);
        pool.batchUnstake(ids);

        assertEq(arc.balanceOf(alice) - arcBefore, 100 * ARC_UNIT, "ARC wrong");
        assertEq(usdt.balanceOf(alice), usdtBefore, "USDT should not have moved");
    }

    // 14.7 — batchUnstake proportional rewards match single unstakes
    function test_BatchUnstake_RewardsMatchSingleUnstake() public {
        uint256 sid1 = _stake(alice, 30 * ARC_UNIT);
        uint256 sid2 = _stake(alice, 70 * ARC_UNIT);
        _notify(1000 * USDT_UNIT); // 300 + 700

        uint256 usdtBefore = usdt.balanceOf(alice);
        uint256[] memory ids = new uint256[](2);
        ids[0] = sid1;
        ids[1] = sid2;
        vm.prank(alice);
        pool.batchUnstake(ids);

        assertEq(usdt.balanceOf(alice) - usdtBefore, 1000 * USDT_UNIT, "batch payout wrong");
    }

    // 14.8 — USDT frozen: all rewards land in frozenRewards, ARC still returned
    function test_BatchUnstake_UsdtFrozen_AllRewardsFrozen() public {
        // Deploy a freezable pool for this test
        MockFreezableUSDT freezableUsdt = new MockFreezableUSDT();
        MockLP frozenLp = new MockLP();
        MockUniswapV2Router frozenRouter = new MockUniswapV2Router(address(frozenLp));
        YieldPool frozenPool =
            new YieldPool(address(arc), address(freezableUsdt), rewarder, lpActivatorAddr, address(frozenRouter));

        arc.mint(alice, 0); // alice already has enough
        vm.prank(alice);
        arc.approve(address(frozenPool), type(uint256).max);

        freezableUsdt.mint(rewarder, 10_000_000 * USDT_UNIT);
        vm.prank(rewarder);
        freezableUsdt.approve(address(frozenPool), type(uint256).max);

        vm.prank(alice);
        frozenPool.stake(50 * ARC_UNIT);
        uint256 sid1 = frozenPool.nextStakeId() - 1;
        vm.prank(alice);
        frozenPool.stake(50 * ARC_UNIT);
        uint256 sid2 = frozenPool.nextStakeId() - 1;

        vm.prank(rewarder);
        frozenPool.notifyReward(1000 * USDT_UNIT);

        freezableUsdt.setTransferReverts(true);

        uint256 arcBefore = arc.balanceOf(alice);
        uint256[] memory ids = new uint256[](2);
        ids[0] = sid1;
        ids[1] = sid2;
        vm.prank(alice);
        frozenPool.batchUnstake(ids);

        assertEq(arc.balanceOf(alice) - arcBefore, 100 * ARC_UNIT, "ARC not returned");
        assertEq(frozenPool.frozenRewards(alice), 1000 * USDT_UNIT, "frozen total wrong");
        assertEq(freezableUsdt.balanceOf(alice), 0, "no USDT should transfer");
    }

    // 14.9 — Fuzz: batch of N positions returns exactly totalStaked and totalReward
    function testFuzz_BatchUnstake_ConservesTokens(uint256 n, uint256 reward) public {
        n = bound(n, 1, 20);
        reward = bound(reward, n * USDT_UNIT, 1_000_000 * USDT_UNIT);

        usdt.mint(rewarder, reward);
        vm.prank(rewarder);
        usdt.approve(address(pool), reward);

        uint256[] memory ids = new uint256[](n);
        uint256 totalArcStaked;
        for (uint256 i; i < n; ++i) {
            uint256 amt = (i + 1) * ARC_UNIT;
            arc.mint(alice, amt);
            vm.prank(alice);
            arc.approve(address(pool), type(uint256).max);
            ids[i] = _stake(alice, amt);
            totalArcStaked += amt;
        }
        _notify(reward);

        uint256 arcBefore = arc.balanceOf(alice);
        uint256 usdtBefore = usdt.balanceOf(alice);
        vm.prank(alice);
        pool.batchUnstake(ids);

        assertEq(arc.balanceOf(alice) - arcBefore, totalArcStaked, "ARC conservation broken");
        // Floor division can truncate up to 1 wei per position, so max loss = n
        assertApproxEqAbs(usdt.balanceOf(alice) - usdtBefore, reward, n, "USDT conservation broken");
        assertEq(pool.totalStaked(), 0, "totalStaked should be 0");
    }
}

// ══════════════════════════════════════════════════════════════════════════════
// §15  LP mode switch — access control & state machine
// ══════════════════════════════════════════════════════════════════════════════

contract Test_LpModeSwitch is YieldPoolTest {
    // 15.1 — Only lpActivator can call activateLpMode
    function test_ActivateLpMode_AccessControl() public {
        vm.prank(attacker);
        vm.expectRevert(YieldPoolErrors.NotLpActivator.selector);
        pool.activateLpMode(address(lp));
    }

    // 15.2 — activateLpMode can only be called once
    function test_ActivateLpMode_OnlyOnce() public {
        _activateLpMode();
        vm.prank(lpActivatorAddr);
        vm.expectRevert(YieldPoolErrors.LpModeAlreadyActive.selector);
        pool.activateLpMode(address(lp));
    }

    // 15.3 — Invalid LP token addresses are rejected
    function test_ActivateLpMode_InvalidLpToken() public {
        vm.prank(lpActivatorAddr);
        vm.expectRevert(YieldPoolErrors.InvalidLpToken.selector);
        pool.activateLpMode(address(0));

        vm.prank(lpActivatorAddr);
        vm.expectRevert(YieldPoolErrors.InvalidLpToken.selector);
        pool.activateLpMode(address(arc));

        vm.prank(lpActivatorAddr);
        vm.expectRevert(YieldPoolErrors.InvalidLpToken.selector);
        pool.activateLpMode(address(usdt));
    }

    // 15.4 — After switch, stake() is permanently disabled
    function test_Stake_BlockedAfterLpMode() public {
        _activateLpMode();
        vm.prank(alice);
        vm.expectRevert(YieldPoolErrors.ArcStakingDisabled.selector);
        pool.stake(100 * ARC_UNIT);
    }

    // 15.5 — addLiquidityAndStake reverts before LP mode is active
    function test_AddLiquidityAndStake_RevertsBeforeLpMode() public {
        _prepareForLp(alice, 1000 * USDT_UNIT);
        vm.prank(alice);
        vm.expectRevert(YieldPoolErrors.LpModeNotActive.selector);
        pool.addLiquidityAndStake(100 * ARC_UNIT, 1000 * USDT_UNIT, 0, 0);
    }

    // 15.6 — lpModeActive flag and lpToken are set correctly after switch
    function test_ActivateLpMode_StateCorrect() public {
        assertFalse(pool.lpModeActive(), "should start as ARC mode");
        _activateLpMode();
        assertTrue(pool.lpModeActive(), "should be LP mode after switch");
        assertEq(pool.lpToken(), address(lp), "lpToken not set");
    }
}

// ══════════════════════════════════════════════════════════════════════════════
// §16  ARC stakers during and after LP mode transition
// ══════════════════════════════════════════════════════════════════════════════

contract Test_ArcStakersAfterSwitch is YieldPoolTest {
    // 16.1 — ARC stakers can still unstake after the switch
    function test_ArcStakers_CanUnstakeAfterSwitch() public {
        uint256 sid = _stake(alice, 100 * ARC_UNIT);
        _notify(1000 * USDT_UNIT);
        _activateLpMode();

        uint256 arcBefore = arc.balanceOf(alice);
        uint256 usdtBefore = usdt.balanceOf(alice);
        _unstake(alice, sid);

        assertEq(arc.balanceOf(alice) - arcBefore, 100 * ARC_UNIT, "ARC not returned after switch");
        assertEq(usdt.balanceOf(alice) - usdtBefore, 1000 * USDT_UNIT, "reward not paid after switch");
    }

    // 16.2 — ARC stakers stop earning after switch; notifyReward feeds LP pool
    function test_ArcStakers_NoNewRewardsAfterSwitch() public {
        uint256 sid = _stake(alice, 100 * ARC_UNIT);
        _notify(500 * USDT_UNIT); // alice earns 500 in ARC mode

        uint256 accBefore = pool.accRewardPerShare();
        _activateLpMode();

        // notifyReward now feeds LP pool — ARC accumulator must not change
        _notify(1000 * USDT_UNIT);

        assertEq(pool.accRewardPerShare(), accBefore, "ARC accumulator should be frozen");
        assertEq(pool.pendingReward(sid), 500 * USDT_UNIT, "ARC staker must not earn LP-mode rewards");
    }

    // 16.3 — ARC stakers can claim accrued rewards after switch
    function test_ArcStakers_CanClaimAfterSwitch() public {
        uint256 sid = _stake(alice, 100 * ARC_UNIT);
        _notify(1000 * USDT_UNIT);
        _activateLpMode();

        uint256 before = usdt.balanceOf(alice);
        _claim(alice, sid);
        assertEq(usdt.balanceOf(alice) - before, 1000 * USDT_UNIT, "accrued reward not claimable after switch");
    }

    // 16.4 — queuedLpRewards fills when notifyReward is called with no LP stakers yet
    function test_AfterSwitch_NotifyReward_QueuesWhenNoLpStakers() public {
        _activateLpMode();
        _notify(1000 * USDT_UNIT);
        assertEq(pool.queuedLpRewards(), 1000 * USDT_UNIT, "reward should be queued");
        assertEq(pool.accEligibleRewardPerArc(), 0, "LP accumulator must stay 0");
    }
}

// ══════════════════════════════════════════════════════════════════════════════
// §17  LP staking — 7-day minimum eligibility
// ══════════════════════════════════════════════════════════════════════════════

contract Test_LpStaking is YieldPoolTest {
    function setUp() public override {
        super.setUp();
        _activateLpMode();
    }

    // 17.1 — addLiquidityAndStake records stake with correct eligibleDay and enrolled=false
    function test_LpStake_StateCorrect() public {
        uint256 arcAmt = 100 * ARC_UNIT;
        uint256 usdtAmt = 1000 * USDT_UNIT;
        _prepareForLp(alice, usdtAmt);

        uint256 lpId = _addLpStake(alice, arcAmt, usdtAmt);

        (uint256 lpAmount, uint256 arcContrib,, uint256 eligibleDay, address owner, bool active, bool enrolled) =
            pool.lpStakes(lpId);

        assertEq(owner, alice, "owner wrong");
        assertTrue(active, "stake not active");
        assertFalse(enrolled, "should not be enrolled at stake time");
        assertEq(arcContrib, arcAmt, "arcContributed wrong");
        assertGt(lpAmount, 0, "no LP tokens minted");
        assertEq(eligibleDay, (block.timestamp + 7 days) / 1 days, "eligibleDay wrong");
        assertEq(pool.totalLpArcContributed(), arcAmt, "totalLpArcContributed wrong");
    }

    // 17.2 — LP tokens are held by the pool contract after stake
    function test_LpStake_LpTokensHeldByPool() public {
        _prepareForLp(alice, 1000 * USDT_UNIT);
        _addLpStake(alice, 100 * ARC_UNIT, 1000 * USDT_UNIT);

        assertGt(lp.balanceOf(address(pool)), 0, "pool should hold LP tokens");
        assertEq(lp.balanceOf(alice), 0, "alice should not hold LP tokens");
    }

    // 17.3 — claimLpReward reverts with StakeNotYetEligible before 7-day minimum
    function test_LpStake_ClaimBefore7Days_Reverts() public {
        _prepareForLp(alice, 1000 * USDT_UNIT);
        uint256 lpId = _addLpStake(alice, 100 * ARC_UNIT, 1000 * USDT_UNIT);

        vm.warp(block.timestamp + 6 days);
        _notify(500 * USDT_UNIT); // reward queued; alice not eligible yet

        vm.prank(alice);
        vm.expectRevert(YieldPoolErrors.StakeNotYetEligible.selector);
        pool.claimLpReward(lpId);
    }

    // 17.4 — Single staker earns full reward after the 7-day minimum has elapsed
    function test_LpStake_SingleStaker_EarnsFullRewardAfterMinDuration() public {
        _prepareForLp(alice, 1000 * USDT_UNIT);
        uint256 lpId = _addLpStake(alice, 100 * ARC_UNIT, 1000 * USDT_UNIT);

        vm.warp(block.timestamp + 7 days);
        _notify(500 * USDT_UNIT);

        assertEq(pool.pendingLpReward(lpId), 500 * USDT_UNIT, "single staker should earn full reward");

        uint256 before = usdt.balanceOf(alice);
        vm.prank(alice);
        pool.claimLpReward(lpId);
        assertEq(usdt.balanceOf(alice) - before, 500 * USDT_UNIT, "claimed wrong amount");
        assertEq(pool.pendingLpReward(lpId), 0, "pending should be 0 after claim");
    }

    // 17.5 — Reward notified before any eligible ARC is queued; flushed when first epoch arrives
    function test_LpStake_PreEligibilityNotify_QueuedThenFlushed() public {
        _prepareForLp(alice, 1000 * USDT_UNIT);
        uint256 lpId = _addLpStake(alice, 100 * ARC_UNIT, 1000 * USDT_UNIT);

        // Notify before 7 days — totalEligibleArc is 0 so reward queues.
        _notify(1000 * USDT_UNIT);
        assertEq(pool.queuedLpRewards(), 1000 * USDT_UNIT, "reward should be queued");
        assertEq(pool.pendingLpReward(lpId), 0, "stake not eligible yet: must show 0");

        // After 7 days, second notify flushes queued amount + new amount together.
        vm.warp(block.timestamp + 7 days);
        _notify(500 * USDT_UNIT);

        assertEq(pool.queuedLpRewards(), 0, "queued should be cleared");
        assertEq(pool.pendingLpReward(lpId), 1500 * USDT_UNIT, "should earn queued + new");
    }

    // 17.6 — Two stakers both past 7 days split rewards proportionally by arcContributed
    function test_LpStake_TwoStakers_ProportionalAfterMinDuration() public {
        _prepareForLp(alice, 1000 * USDT_UNIT);
        _prepareForLp(bob, 1000 * USDT_UNIT);

        uint256 lpIdA = _addLpStake(alice, 60 * ARC_UNIT, 600 * USDT_UNIT); // 60 %
        uint256 lpIdB = _addLpStake(bob, 40 * ARC_UNIT, 400 * USDT_UNIT); // 40 %

        vm.warp(block.timestamp + 7 days);
        _notify(1000 * USDT_UNIT);

        assertEq(pool.pendingLpReward(lpIdA), 600 * USDT_UNIT, "alice LP reward wrong");
        assertEq(pool.pendingLpReward(lpIdB), 400 * USDT_UNIT, "bob LP reward wrong");
    }

    // 17.7 — Staker whose 7 days haven't elapsed misses an epoch; later becomes eligible
    //         and earns proportionally from epochs after that point only
    function test_LpStake_LateStaker_MissesEarlyEpoch() public {
        _prepareForLp(alice, 1000 * USDT_UNIT);
        uint256 lpIdA = _addLpStake(alice, 100 * ARC_UNIT, 1000 * USDT_UNIT);

        // Alice eligible after 7 days; epoch 1 goes entirely to Alice.
        vm.warp(block.timestamp + 7 days);
        _notify(1000 * USDT_UNIT);

        // Bob stakes after epoch 1; his eligibleDay is 7 more days from now.
        _prepareForLp(bob, 1000 * USDT_UNIT);
        uint256 lpIdB = _addLpStake(bob, 100 * ARC_UNIT, 1000 * USDT_UNIT);

        assertEq(pool.pendingLpReward(lpIdA), 1000 * USDT_UNIT, "alice must earn full epoch 1");
        assertEq(pool.pendingLpReward(lpIdB), 0, "bob must earn 0 from epoch 1");

        // After Bob's 7 days, epoch 2 splits 50/50.
        vm.warp(block.timestamp + 7 days);
        _notify(1000 * USDT_UNIT);

        assertEq(pool.pendingLpReward(lpIdA), 1500 * USDT_UNIT, "alice epoch1 + half epoch2 wrong");
        assertEq(pool.pendingLpReward(lpIdB), 500 * USDT_UNIT, "bob half epoch2 wrong");
    }

    // 17.8 — claimLpReward enrolls the stake and resets pending to 0
    function test_ClaimLpReward_EnrollsAndResets() public {
        _prepareForLp(alice, 1000 * USDT_UNIT);
        uint256 lpId = _addLpStake(alice, 100 * ARC_UNIT, 1000 * USDT_UNIT);

        vm.warp(block.timestamp + 7 days);
        _notify(800 * USDT_UNIT);

        uint256 before = usdt.balanceOf(alice);
        vm.prank(alice);
        pool.claimLpReward(lpId);

        assertEq(usdt.balanceOf(alice) - before, 800 * USDT_UNIT, "claim amount wrong");
        assertEq(pool.pendingLpReward(lpId), 0, "pending should be 0 after claim");

        (,,,,,, bool enrolled) = pool.lpStakes(lpId);
        assertTrue(enrolled, "stake should be enrolled after first claim");
    }

    // 17.9 — claimLpReward reverts NoRewardToClaim when eligible but no epoch has run
    function test_ClaimLpReward_EligibleButNoEpoch_Reverts() public {
        _prepareForLp(alice, 1000 * USDT_UNIT);
        uint256 lpId = _addLpStake(alice, 100 * ARC_UNIT, 1000 * USDT_UNIT);

        // Past 7 days but no notifyReward → accumulator still 0 → reward is 0.
        vm.warp(block.timestamp + 7 days);

        vm.prank(alice);
        vm.expectRevert(YieldPoolErrors.NoRewardToClaim.selector);
        pool.claimLpReward(lpId);
    }

    // 17.10 — Non-owner cannot claim another user's LP reward
    function test_ClaimLpReward_WrongOwner_Reverts() public {
        _prepareForLp(alice, 1000 * USDT_UNIT);
        uint256 lpId = _addLpStake(alice, 100 * ARC_UNIT, 1000 * USDT_UNIT);

        vm.warp(block.timestamp + 7 days);
        _notify(1000 * USDT_UNIT);

        vm.prank(attacker);
        vm.expectRevert(YieldPoolErrors.NotLpStakeOwner.selector);
        pool.claimLpReward(lpId);
    }

    // 17.11 — Claiming an inactive stake reverts
    function test_ClaimLpReward_NotActive_Reverts() public {
        _prepareForLp(alice, 1000 * USDT_UNIT);
        uint256 lpId = _addLpStake(alice, 100 * ARC_UNIT, 1000 * USDT_UNIT);

        vm.prank(alice);
        pool.cancelLpStake(lpId, 0, 0);

        vm.prank(alice);
        vm.expectRevert(YieldPoolErrors.LpStakeNotActive.selector);
        pool.claimLpReward(lpId);
    }
}

// ══════════════════════════════════════════════════════════════════════════════
// §18  LP stake cancellation
// ══════════════════════════════════════════════════════════════════════════════

contract Test_LpCancel is YieldPoolTest {
    function setUp() public override {
        super.setUp();
        _activateLpMode();
    }

    // 18.1 — Cancelling before eligibility returns tokens; no reward paid
    function test_CancelLpStake_BeforeEligible_ReturnsTokensNoReward() public {
        uint256 arcAmt = 100 * ARC_UNIT;
        uint256 usdtAmt = 1000 * USDT_UNIT;
        _prepareForLp(alice, usdtAmt);

        uint256 arcBefore = arc.balanceOf(alice);
        uint256 usdtBefore = usdt.balanceOf(alice);

        uint256 lpId = _addLpStake(alice, arcAmt, usdtAmt);

        // Cancel within 7-day window — no reward expected.
        vm.warp(block.timestamp + 3 days);
        vm.prank(alice);
        pool.cancelLpStake(lpId, 0, 0);

        assertEq(arc.balanceOf(alice), arcBefore, "ARC not returned on early cancel");
        assertEq(usdt.balanceOf(alice), usdtBefore, "USDT not returned on early cancel");
    }

    // 18.2 — Cancelling before eligibility removes ARC from the eligibility queue
    function test_CancelLpStake_BeforeEligible_RemovesFromQueue() public {
        _prepareForLp(alice, 1000 * USDT_UNIT);
        uint256 lpId = _addLpStake(alice, 100 * ARC_UNIT, 1000 * USDT_UNIT);

        (, uint256 arcContrib,, uint256 eligibleDay,,,) = pool.lpStakes(lpId);
        assertEq(pool.eligibilityByDay(eligibleDay), arcContrib, "ARC should be in queue");

        vm.prank(alice);
        pool.cancelLpStake(lpId, 0, 0);

        assertEq(pool.eligibilityByDay(eligibleDay), 0, "ARC not removed from queue");
        assertEq(pool.totalLpArcContributed(), 0, "totalLpArcContributed not zeroed");
        assertEq(pool.totalEligibleArc(), 0, "totalEligibleArc should remain 0");
    }

    // 18.3 — Cancelling after eligibility returns tokens and pays accrued reward
    function test_CancelLpStake_AfterEligible_ReturnsTokensAndReward() public {
        uint256 arcAmt = 100 * ARC_UNIT;
        uint256 usdtAmt = 1000 * USDT_UNIT;
        _prepareForLp(alice, usdtAmt);

        uint256 arcBefore = arc.balanceOf(alice);
        uint256 usdtBefore = usdt.balanceOf(alice);

        uint256 lpId = _addLpStake(alice, arcAmt, usdtAmt);

        vm.warp(block.timestamp + 7 days);
        _notify(600 * USDT_UNIT);

        vm.prank(alice);
        pool.cancelLpStake(lpId, 0, 0);

        // Tokens returned in full; reward on top.
        assertEq(arc.balanceOf(alice), arcBefore, "ARC not returned on cancel");
        assertGe(usdt.balanceOf(alice), usdtBefore + 600 * USDT_UNIT, "reward not paid on cancel");
    }

    // 18.4 — Cancelling after eligibility removes ARC from the eligible pool
    function test_CancelLpStake_AfterEligible_RemovesFromEligiblePool() public {
        _prepareForLp(alice, 1000 * USDT_UNIT);
        uint256 lpId = _addLpStake(alice, 100 * ARC_UNIT, 1000 * USDT_UNIT);

        vm.warp(block.timestamp + 7 days);
        _notify(1 * USDT_UNIT); // triggers _processEligibility, promotes ARC to eligible

        assertGt(pool.totalEligibleArc(), 0, "should have eligible ARC after notify");

        vm.prank(alice);
        pool.cancelLpStake(lpId, 0, 0);

        assertEq(pool.totalEligibleArc(), 0, "totalEligibleArc should be 0 after cancel");
        assertEq(pool.totalLpArcContributed(), 0, "totalLpArcContributed should be 0");
    }

    // 18.5 — Cancelled stake is inactive and cannot be cancelled again
    function test_CancelLpStake_InactiveAfterCancel() public {
        _prepareForLp(alice, 1000 * USDT_UNIT);
        uint256 lpId = _addLpStake(alice, 100 * ARC_UNIT, 1000 * USDT_UNIT);

        vm.prank(alice);
        pool.cancelLpStake(lpId, 0, 0);

        vm.prank(alice);
        vm.expectRevert(YieldPoolErrors.LpStakeNotActive.selector);
        pool.cancelLpStake(lpId, 0, 0);
    }

    // 18.6 — Non-owner cannot cancel another user's LP stake
    function test_CancelLpStake_WrongOwner_Reverts() public {
        _prepareForLp(alice, 1000 * USDT_UNIT);
        uint256 lpId = _addLpStake(alice, 100 * ARC_UNIT, 1000 * USDT_UNIT);

        vm.prank(attacker);
        vm.expectRevert(YieldPoolErrors.NotLpStakeOwner.selector);
        pool.cancelLpStake(lpId, 0, 0);
    }

    // 18.7 — Remaining LP stakers are unaffected when a peer cancels after eligibility
    function test_CancelLpStake_PeerUnaffected() public {
        _prepareForLp(alice, 1000 * USDT_UNIT);
        _prepareForLp(bob, 1000 * USDT_UNIT);

        uint256 lpIdA = _addLpStake(alice, 50 * ARC_UNIT, 500 * USDT_UNIT);
        uint256 lpIdB = _addLpStake(bob, 50 * ARC_UNIT, 500 * USDT_UNIT);

        vm.warp(block.timestamp + 7 days);
        _notify(1000 * USDT_UNIT); // alice = 500, bob = 500

        vm.prank(bob);
        pool.cancelLpStake(lpIdB, 0, 0);

        assertEq(pool.pendingLpReward(lpIdA), 500 * USDT_UNIT, "alice reward affected by bob cancel");
    }

    // 18.8 — getUserLpStakeIds returns all IDs including cancelled ones
    function test_GetUserLpStakeIds_IncludesCancelled() public {
        _prepareForLp(alice, 2000 * USDT_UNIT);
        uint256 lpId1 = _addLpStake(alice, 50 * ARC_UNIT, 500 * USDT_UNIT);
        uint256 lpId2 = _addLpStake(alice, 50 * ARC_UNIT, 500 * USDT_UNIT);

        vm.prank(alice);
        pool.cancelLpStake(lpId1, 0, 0);

        uint256[] memory ids = pool.getUserLpStakeIds(alice);
        assertEq(ids.length, 2, "should return both IDs");
        assertEq(ids[0], lpId1);
        assertEq(ids[1], lpId2);
    }
}

// ══════════════════════════════════════════════════════════════════════════════
// §18b  cancelLpStake — frozen USDT reward path
//
// Uses MockFreezableUSDT so USDT can be paused mid-test.  LP liquidity must
// always be returned; only the USDT reward portion is frozen.
// ══════════════════════════════════════════════════════════════════════════════

contract Test_LpCancelFrozenRewards is Test {
    uint256 internal constant ARC_UNIT = 1e18;
    uint256 internal constant USDT_UNIT = 1e6;

    YieldPool internal pool;
    MockARC internal arc;
    MockFreezableUSDT internal usdt;
    MockLP internal lp;
    MockUniswapV2Router internal router;

    address internal alice = makeAddr("alice");
    address internal rewarder = makeAddr("rewarder");
    address internal lpActivatorAddr = makeAddr("lpActivator");

    function setUp() public {
        arc = new MockARC();
        usdt = new MockFreezableUSDT();
        lp = new MockLP();
        router = new MockUniswapV2Router(address(lp));
        pool = new YieldPool(address(arc), address(usdt), rewarder, lpActivatorAddr, address(router));

        arc.mint(alice, 1_000_000 * ARC_UNIT);
        usdt.mint(rewarder, 10_000_000 * USDT_UNIT);

        vm.prank(alice);
        arc.approve(address(pool), type(uint256).max);
        vm.prank(rewarder);
        usdt.approve(address(pool), type(uint256).max);

        // Activate LP mode.
        vm.prank(lpActivatorAddr);
        pool.activateLpMode(address(lp));
    }

    function _addLpStake(uint256 usdtAmt, uint256 arcAmt) internal returns (uint256 lpId) {
        usdt.mint(alice, usdtAmt);
        vm.prank(alice);
        usdt.approve(address(pool), type(uint256).max);
        vm.prank(alice);
        pool.addLiquidityAndStake(arcAmt, usdtAmt, 0, 0);
        lpId = pool.nextLpStakeId() - 1;
    }

    function _notify(uint256 amount) internal {
        vm.prank(rewarder);
        pool.notifyReward(amount);
    }

    // 18b.1 — Pool's USDT transfer reverts (simulates pool address blacklisted by USDT):
    //          LP liquidity is still returned; only the reward portion is frozen.
    function test_CancelLpStake_UsdtReverts_LpReturnedRewardFrozen() public {
        uint256 arcBefore = arc.balanceOf(alice);
        uint256 lpId = _addLpStake(1000 * USDT_UNIT, 100 * ARC_UNIT);

        vm.warp(block.timestamp + 7 days);
        _notify(500 * USDT_UNIT);

        // Freeze only transfers FROM the pool; the router can still return USDT to alice.
        usdt.setFrozenSender(address(pool));
        usdt.setTransferReverts(true);

        vm.expectEmit(true, true, false, true);
        emit YieldPoolEvents.RewardFrozen(alice, lpId, 500 * USDT_UNIT);
        vm.prank(alice);
        pool.cancelLpStake(lpId, 0, 0);

        assertEq(arc.balanceOf(alice), arcBefore, "ARC not returned with frozen reward");
        assertEq(pool.frozenRewards(alice), 500 * USDT_UNIT, "reward not frozen");
        // Router transferred the LP's USDT portion; pool's reward portion was frozen.
        assertEq(usdt.balanceOf(alice), 1000 * USDT_UNIT, "router USDT must still reach alice");
    }

    // 18b.2 — Pool's USDT transfer returns false: same frozen path
    function test_CancelLpStake_UsdtReturnsFalse_RewardFrozen() public {
        uint256 lpId = _addLpStake(1000 * USDT_UNIT, 100 * ARC_UNIT);

        vm.warp(block.timestamp + 7 days);
        _notify(500 * USDT_UNIT);

        usdt.setFrozenSender(address(pool));
        usdt.setTransferReturnsFalse(true);

        vm.prank(alice);
        pool.cancelLpStake(lpId, 0, 0);

        assertEq(pool.frozenRewards(alice), 500 * USDT_UNIT, "reward not frozen on false-return");
    }

    // 18b.3 — After pool is removed from the blacklist, claimFrozenRewards recovers the reward
    function test_CancelLpStake_FrozenReward_ClaimableAfterUnfreeze() public {
        uint256 lpId = _addLpStake(1000 * USDT_UNIT, 100 * ARC_UNIT);

        vm.warp(block.timestamp + 7 days);
        _notify(500 * USDT_UNIT);

        usdt.setFrozenSender(address(pool));
        usdt.setTransferReverts(true);
        vm.prank(alice);
        pool.cancelLpStake(lpId, 0, 0);
        assertEq(pool.frozenRewards(alice), 500 * USDT_UNIT);

        // Pool removed from blacklist.
        usdt.setFrozenSender(address(0));
        usdt.setTransferReverts(false);

        uint256 before = usdt.balanceOf(alice);
        vm.prank(alice);
        pool.claimFrozenRewards();

        assertEq(usdt.balanceOf(alice) - before, 500 * USDT_UNIT, "frozen LP reward not recovered");
        assertEq(pool.frozenRewards(alice), 0, "frozen balance not cleared");
    }

    // 18b.4 — No reward (stake not yet eligible): cancel succeeds; frozenRewards untouched
    function test_CancelLpStake_NoReward_FrozenMapUntouched() public {
        uint256 lpId = _addLpStake(1000 * USDT_UNIT, 100 * ARC_UNIT);
        // Cancel before 7-day window — reward is 0; no USDT transfer attempted by pool.

        usdt.setFrozenSender(address(pool));
        usdt.setTransferReverts(true);
        vm.prank(alice);
        pool.cancelLpStake(lpId, 0, 0);

        assertEq(pool.frozenRewards(alice), 0, "no frozen entry expected for zero reward");
    }

    // 18b.5 — LpRewardClaimed NOT emitted when reward is frozen; only RewardFrozen fires
    function test_CancelLpStake_NoLpRewardClaimedEventOnFreeze() public {
        uint256 lpId = _addLpStake(1000 * USDT_UNIT, 100 * ARC_UNIT);

        vm.warp(block.timestamp + 7 days);
        _notify(500 * USDT_UNIT);

        usdt.setFrozenSender(address(pool));
        usdt.setTransferReverts(true);

        vm.recordLogs();
        vm.prank(alice);
        pool.cancelLpStake(lpId, 0, 0);

        Vm.Log[] memory logs = vm.getRecordedLogs();
        bytes32 lpRewardClaimedSig = keccak256("LpRewardClaimed(address,uint256,uint256)");
        bytes32 rewardFrozenSig = keccak256("RewardFrozen(address,uint256,uint256)");
        bool sawFrozen;
        for (uint256 i; i < logs.length; ++i) {
            assertTrue(logs[i].topics[0] != lpRewardClaimedSig, "LpRewardClaimed must not fire on frozen reward");
            if (logs[i].topics[0] == rewardFrozenSig) sawFrozen = true;
        }
        assertTrue(sawFrozen, "RewardFrozen must fire");
    }
}

// ══════════════════════════════════════════════════════════════════════════════
// §19  batchClaimLpReward
// ══════════════════════════════════════════════════════════════════════════════

contract Test_BatchClaimLpReward is YieldPoolTest {
    function setUp() public override {
        super.setUp();
        _activateLpMode();
    }

    // 19.1 — Empty array reverts
    function test_BatchClaimLpReward_EmptyArray_Reverts() public {
        vm.prank(alice);
        vm.expectRevert(YieldPoolErrors.EmptyStakeIds.selector);
        pool.batchClaimLpReward(new uint256[](0));
    }

    // 19.2 — Array longer than 20 reverts
    function test_BatchClaimLpReward_TooLarge_Reverts() public {
        vm.prank(alice);
        vm.expectRevert(YieldPoolErrors.BatchTooLarge.selector);
        pool.batchClaimLpReward(new uint256[](21));
    }

    // 19.3 — Claiming from an inactive stake reverts
    function test_BatchClaimLpReward_NotActive_Reverts() public {
        _prepareForLp(alice, 1000 * USDT_UNIT);
        uint256 lpId = _addLpStake(alice, 100 * ARC_UNIT, 1000 * USDT_UNIT);
        vm.prank(alice);
        pool.cancelLpStake(lpId, 0, 0);

        uint256[] memory ids = new uint256[](1);
        ids[0] = lpId;
        vm.prank(alice);
        vm.expectRevert(YieldPoolErrors.LpStakeNotActive.selector);
        pool.batchClaimLpReward(ids);
    }

    // 19.4 — Non-owner cannot claim another user's LP rewards
    function test_BatchClaimLpReward_WrongOwner_Reverts() public {
        _prepareForLp(alice, 1000 * USDT_UNIT);
        uint256 lpId = _addLpStake(alice, 100 * ARC_UNIT, 1000 * USDT_UNIT);
        vm.warp(block.timestamp + 7 days);
        _notify(500 * USDT_UNIT);

        uint256[] memory ids = new uint256[](1);
        ids[0] = lpId;
        vm.prank(attacker);
        vm.expectRevert(YieldPoolErrors.NotLpStakeOwner.selector);
        pool.batchClaimLpReward(ids);
    }

    // 19.5 — Reverts if any stake has not yet passed its 7-day window
    function test_BatchClaimLpReward_NotEligible_Reverts() public {
        _prepareForLp(alice, 2000 * USDT_UNIT);
        uint256 lpId1 = _addLpStake(alice, 100 * ARC_UNIT, 1000 * USDT_UNIT);
        vm.warp(block.timestamp + 7 days);
        // Second stake opened after 7-day warp — its window hasn't passed yet.
        uint256 lpId2 = _addLpStake(alice, 100 * ARC_UNIT, 1000 * USDT_UNIT);
        _notify(500 * USDT_UNIT);

        uint256[] memory ids = new uint256[](2);
        ids[0] = lpId1;
        ids[1] = lpId2; // not eligible yet
        vm.prank(alice);
        vm.expectRevert(YieldPoolErrors.StakeNotYetEligible.selector);
        pool.batchClaimLpReward(ids);
    }

    // 19.6 — Zero total reward reverts
    function test_BatchClaimLpReward_ZeroReward_Reverts() public {
        _prepareForLp(alice, 1000 * USDT_UNIT);
        uint256 lpId = _addLpStake(alice, 100 * ARC_UNIT, 1000 * USDT_UNIT);
        vm.warp(block.timestamp + 7 days);
        // No notifyReward — nothing to claim.

        uint256[] memory ids = new uint256[](1);
        ids[0] = lpId;
        vm.prank(alice);
        vm.expectRevert(YieldPoolErrors.NoRewardToClaim.selector);
        pool.batchClaimLpReward(ids);
    }

    // 19.7 — Two stakes: batch pays both in one transfer
    function test_BatchClaimLpReward_TwoStakes_PaidTogether() public {
        _prepareForLp(alice, 2000 * USDT_UNIT);
        uint256 lpId1 = _addLpStake(alice, 60 * ARC_UNIT, 600 * USDT_UNIT); // 60 %
        uint256 lpId2 = _addLpStake(alice, 40 * ARC_UNIT, 400 * USDT_UNIT); // 40 %

        vm.warp(block.timestamp + 7 days);
        _notify(1000 * USDT_UNIT);

        uint256 before = usdt.balanceOf(alice);
        uint256[] memory ids = new uint256[](2);
        ids[0] = lpId1;
        ids[1] = lpId2;
        vm.prank(alice);
        pool.batchClaimLpReward(ids);

        assertEq(usdt.balanceOf(alice) - before, 1000 * USDT_UNIT, "batch total wrong");
        assertEq(pool.pendingLpReward(lpId1), 0, "lpId1 not settled");
        assertEq(pool.pendingLpReward(lpId2), 0, "lpId2 not settled");
    }

    // 19.8 — Duplicate ID does not double-pay (second settle returns 0)
    function test_BatchClaimLpReward_DuplicateId_NoDoublePay() public {
        _prepareForLp(alice, 1000 * USDT_UNIT);
        uint256 lpId = _addLpStake(alice, 100 * ARC_UNIT, 1000 * USDT_UNIT);
        vm.warp(block.timestamp + 7 days);
        _notify(800 * USDT_UNIT);

        uint256 before = usdt.balanceOf(alice);
        uint256[] memory ids = new uint256[](2);
        ids[0] = lpId;
        ids[1] = lpId; // duplicate
        vm.prank(alice);
        pool.batchClaimLpReward(ids);

        assertEq(usdt.balanceOf(alice) - before, 800 * USDT_UNIT, "duplicate paid twice");
    }

    // 19.9 — Claim → new epoch → batchClaim: only delta paid the second time
    function test_BatchClaimLpReward_MultiEpoch_OnlyDeltaPaid() public {
        _prepareForLp(alice, 1000 * USDT_UNIT);
        uint256 lpId = _addLpStake(alice, 100 * ARC_UNIT, 1000 * USDT_UNIT);
        vm.warp(block.timestamp + 7 days);

        _notify(600 * USDT_UNIT); // epoch 1
        vm.prank(alice);
        pool.claimLpReward(lpId); // claim epoch 1

        _notify(400 * USDT_UNIT); // epoch 2

        uint256 before = usdt.balanceOf(alice);
        uint256[] memory ids = new uint256[](1);
        ids[0] = lpId;
        vm.prank(alice);
        pool.batchClaimLpReward(ids); // should pay only epoch 2

        assertEq(usdt.balanceOf(alice) - before, 400 * USDT_UNIT, "only epoch 2 delta expected");
    }
}

// ══════════════════════════════════════════════════════════════════════════════
// §20  batchCancelLpStake
// ══════════════════════════════════════════════════════════════════════════════

contract Test_BatchCancelLpStake is YieldPoolTest {
    // Helper: builds three equal-length zero-filled slippage arrays.
    function _noSlippage(uint256 n) internal pure returns (uint256[] memory a, uint256[] memory b) {
        a = new uint256[](n);
        b = new uint256[](n);
    }

    function setUp() public override {
        super.setUp();
        _activateLpMode();
    }

    // 20.1 — Empty array reverts
    function test_BatchCancelLpStake_EmptyArray_Reverts() public {
        (uint256[] memory a, uint256[] memory b) = _noSlippage(0);
        vm.prank(alice);
        vm.expectRevert(YieldPoolErrors.EmptyStakeIds.selector);
        pool.batchCancelLpStake(new uint256[](0), a, b);
    }

    // 20.2 — Array longer than 20 reverts
    function test_BatchCancelLpStake_TooLarge_Reverts() public {
        (uint256[] memory a, uint256[] memory b) = _noSlippage(21);
        vm.prank(alice);
        vm.expectRevert(YieldPoolErrors.BatchTooLarge.selector);
        pool.batchCancelLpStake(new uint256[](21), a, b);
    }

    // 20.3 — Mismatched array lengths revert
    function test_BatchCancelLpStake_LengthMismatch_Reverts() public {
        _prepareForLp(alice, 1000 * USDT_UNIT);
        uint256 lpId = _addLpStake(alice, 100 * ARC_UNIT, 1000 * USDT_UNIT);

        uint256[] memory ids = new uint256[](1);
        ids[0] = lpId;
        uint256[] memory a = new uint256[](2); // wrong length
        uint256[] memory b = new uint256[](1);

        vm.prank(alice);
        vm.expectRevert(YieldPoolErrors.ArrayLengthMismatch.selector);
        pool.batchCancelLpStake(ids, a, b);
    }

    // 20.4 — Non-owner cannot cancel another user's stake
    function test_BatchCancelLpStake_WrongOwner_Reverts() public {
        _prepareForLp(alice, 1000 * USDT_UNIT);
        uint256 lpId = _addLpStake(alice, 100 * ARC_UNIT, 1000 * USDT_UNIT);

        uint256[] memory ids = new uint256[](1);
        ids[0] = lpId;
        (uint256[] memory a, uint256[] memory b) = _noSlippage(1);

        vm.prank(attacker);
        vm.expectRevert(YieldPoolErrors.NotLpStakeOwner.selector);
        pool.batchCancelLpStake(ids, a, b);
    }

    // 20.5 — Already-cancelled stake reverts
    function test_BatchCancelLpStake_InactiveStake_Reverts() public {
        _prepareForLp(alice, 1000 * USDT_UNIT);
        uint256 lpId = _addLpStake(alice, 100 * ARC_UNIT, 1000 * USDT_UNIT);
        vm.prank(alice);
        pool.cancelLpStake(lpId, 0, 0); // now inactive

        uint256[] memory ids = new uint256[](1);
        ids[0] = lpId;
        (uint256[] memory a, uint256[] memory b) = _noSlippage(1);

        vm.prank(alice);
        vm.expectRevert(YieldPoolErrors.LpStakeNotActive.selector);
        pool.batchCancelLpStake(ids, a, b);
    }

    // 20.6 — Cancel before eligibility: tokens returned, no reward, removed from queue
    function test_BatchCancelLpStake_BeforeEligible_NoReward() public {
        _prepareForLp(alice, 1000 * USDT_UNIT);

        // Capture balances before the stake so we can assert full return.
        uint256 arcBefore = arc.balanceOf(alice);
        uint256 usdtBefore = usdt.balanceOf(alice);

        uint256 lpId = _addLpStake(alice, 100 * ARC_UNIT, 1000 * USDT_UNIT);
        (, uint256 arcContrib,, uint256 eligibleDay,,,) = pool.lpStakes(lpId);

        uint256[] memory ids = new uint256[](1);
        ids[0] = lpId;
        (uint256[] memory a, uint256[] memory b) = _noSlippage(1);

        vm.prank(alice);
        pool.batchCancelLpStake(ids, a, b);

        assertEq(arc.balanceOf(alice), arcBefore, "ARC not returned");
        assertEq(usdt.balanceOf(alice), usdtBefore, "USDT not returned");
        assertEq(pool.eligibilityByDay(eligibleDay), 0, "ARC not removed from queue");
        assertEq(pool.totalLpArcContributed(), 0, "totalLpArcContributed not zeroed");
    }

    // 20.7 — Cancel after eligibility: tokens + reward returned, removed from eligible pool
    function test_BatchCancelLpStake_AfterEligible_ReturnsTokensAndReward() public {
        _prepareForLp(alice, 1000 * USDT_UNIT);

        // Capture balances before the stake so we can assert full return + reward.
        uint256 arcBefore = arc.balanceOf(alice);
        uint256 usdtBefore = usdt.balanceOf(alice);

        uint256 lpId = _addLpStake(alice, 100 * ARC_UNIT, 1000 * USDT_UNIT);

        vm.warp(block.timestamp + 7 days);
        _notify(500 * USDT_UNIT);

        uint256[] memory ids = new uint256[](1);
        ids[0] = lpId;
        (uint256[] memory a, uint256[] memory b) = _noSlippage(1);

        vm.prank(alice);
        pool.batchCancelLpStake(ids, a, b);

        assertEq(arc.balanceOf(alice), arcBefore, "ARC not returned");
        assertGe(usdt.balanceOf(alice), usdtBefore + 500 * USDT_UNIT, "reward not paid");
        assertEq(pool.totalEligibleArc(), 0, "totalEligibleArc not zeroed");
        assertEq(pool.totalLpArcContributed(), 0, "totalLpArcContributed not zeroed");
    }

    // 20.8 — Batch of two stakes: both cancelled, combined reward paid in one transfer
    function test_BatchCancelLpStake_TwoStakes_CombinedReward() public {
        _prepareForLp(alice, 2000 * USDT_UNIT);

        // Capture balances before any stake so we can assert full return + reward.
        uint256 arcBefore = arc.balanceOf(alice);
        uint256 usdtBefore = usdt.balanceOf(alice);

        uint256 lpId1 = _addLpStake(alice, 60 * ARC_UNIT, 600 * USDT_UNIT); // 60 %
        uint256 lpId2 = _addLpStake(alice, 40 * ARC_UNIT, 400 * USDT_UNIT); // 40 %

        vm.warp(block.timestamp + 7 days);
        _notify(1000 * USDT_UNIT); // 600 + 400

        uint256[] memory ids = new uint256[](2);
        ids[0] = lpId1;
        ids[1] = lpId2;
        (uint256[] memory a, uint256[] memory b) = _noSlippage(2);

        vm.prank(alice);
        pool.batchCancelLpStake(ids, a, b);

        assertEq(arc.balanceOf(alice), arcBefore, "ARC not returned");
        assertGe(usdt.balanceOf(alice), usdtBefore + 1000 * USDT_UNIT, "total reward wrong");

        (,,,,, bool active1,) = pool.lpStakes(lpId1);
        (,,,,, bool active2,) = pool.lpStakes(lpId2);
        assertFalse(active1, "lpId1 still active");
        assertFalse(active2, "lpId2 still active");
    }

    // 20.9 — Mix: one stake before eligible, one after — handled correctly in same batch
    function test_BatchCancelLpStake_MixedEligibility() public {
        _prepareForLp(alice, 2000 * USDT_UNIT);
        uint256 lpId1 = _addLpStake(alice, 100 * ARC_UNIT, 1000 * USDT_UNIT);

        vm.warp(block.timestamp + 7 days);
        _notify(1000 * USDT_UNIT); // only lpId1 eligible

        // lpId2 staked after warp — ineligible for another 7 days.
        uint256 lpId2 = _addLpStake(alice, 50 * ARC_UNIT, 500 * USDT_UNIT);

        uint256 usdtBefore = usdt.balanceOf(alice);

        uint256[] memory ids = new uint256[](2);
        ids[0] = lpId1; // eligible: earns 1000 USDT
        ids[1] = lpId2; // not eligible: earns 0 USDT
        (uint256[] memory a, uint256[] memory b) = _noSlippage(2);

        vm.prank(alice);
        pool.batchCancelLpStake(ids, a, b);

        // Only lpId1's reward is paid; lpId2 returns tokens but no reward.
        assertGe(usdt.balanceOf(alice), usdtBefore + 1000 * USDT_UNIT, "reward from eligible stake wrong");
        assertEq(pool.eligibilityByDay(pool.lastProcessedDay() + 7), 0, "ineligible ARC not removed from queue");
        assertEq(pool.totalLpArcContributed(), 0, "totalLpArcContributed not zeroed");
    }

    // 20.10 — Remaining peer's rewards are unaffected by a batch cancel
    function test_BatchCancelLpStake_PeerUnaffected() public {
        _prepareForLp(alice, 1000 * USDT_UNIT);
        _prepareForLp(bob, 1000 * USDT_UNIT);

        uint256 lpIdA = _addLpStake(alice, 50 * ARC_UNIT, 500 * USDT_UNIT);
        uint256 lpIdB = _addLpStake(bob, 50 * ARC_UNIT, 500 * USDT_UNIT);

        vm.warp(block.timestamp + 7 days);
        _notify(1000 * USDT_UNIT); // alice = 500, bob = 500

        uint256[] memory ids = new uint256[](1);
        ids[0] = lpIdA;
        (uint256[] memory a, uint256[] memory b) = _noSlippage(1);

        vm.prank(alice);
        pool.batchCancelLpStake(ids, a, b);

        assertEq(pool.pendingLpReward(lpIdB), 500 * USDT_UNIT, "bob reward affected by alice batch cancel");
    }
}

// ══════════════════════════════════════════════════════════════════════════════
// Mocks for §21–§23
// ══════════════════════════════════════════════════════════════════════════════

/// @dev Router that consumes exactly (amountDesired - 1) of each token so the
///      refund branches in _addLiquidityAndStake (arcAmount > arcUsed,
///      usdtAmount > usdtUsed) are both exercised.
contract MockPartialRouter {
    MockLP internal lp;
    uint256 internal reserveArc;
    uint256 internal reserveUsdt;
    uint256 internal totalLp;

    constructor(address _lp) {
        lp = MockLP(_lp);
    }

    function addLiquidity(
        address tokenA,
        address tokenB,
        uint256 amountADesired,
        uint256 amountBDesired,
        uint256,
        uint256,
        address to,
        uint256
    ) external returns (uint256 amountA, uint256 amountB, uint256 liquidity) {
        amountA = amountADesired - 1;
        amountB = amountBDesired - 1;
        liquidity = amountA;
        IERC20(tokenA).transferFrom(msg.sender, address(this), amountA);
        IERC20(tokenB).transferFrom(msg.sender, address(this), amountB);
        reserveArc += amountA;
        reserveUsdt += amountB;
        totalLp += liquidity;
        lp.mint(to, liquidity);
    }

    function removeLiquidity(
        address tokenA,
        address tokenB,
        uint256 liquidity,
        uint256,
        uint256,
        address to,
        uint256
    ) external returns (uint256 amountA, uint256 amountB) {
        IERC20(address(lp)).transferFrom(msg.sender, address(this), liquidity);
        if (totalLp > 0) {
            amountA = liquidity * reserveArc / totalLp;
            amountB = liquidity * reserveUsdt / totalLp;
        }
        reserveArc -= amountA;
        reserveUsdt -= amountB;
        totalLp -= liquidity;
        IERC20(tokenA).transfer(to, amountA);
        IERC20(tokenB).transfer(to, amountB);
    }
}

/// @dev Router that returns arcUsed == 0, creating LP stakes where
///      arcContributed == 0.  All USDT is consumed normally.
contract MockZeroArcRouter {
    MockLP internal lp;
    uint256 internal reserveUsdt;
    uint256 internal totalLp;

    constructor(address _lp) {
        lp = MockLP(_lp);
    }

    function addLiquidity(
        address,
        address tokenB,
        uint256,
        uint256 amountBDesired,
        uint256,
        uint256,
        address to,
        uint256
    ) external returns (uint256 amountA, uint256 amountB, uint256 liquidity) {
        amountA = 0;
        amountB = amountBDesired;
        liquidity = amountBDesired;
        IERC20(tokenB).transferFrom(msg.sender, address(this), amountB);
        reserveUsdt += amountB;
        totalLp += liquidity;
        lp.mint(to, liquidity);
    }

    function removeLiquidity(
        address,
        address tokenB,
        uint256 liquidity,
        uint256,
        uint256,
        address to,
        uint256
    ) external returns (uint256 amountA, uint256 amountB) {
        IERC20(address(lp)).transferFrom(msg.sender, address(this), liquidity);
        amountA = 0;
        if (totalLp > 0) amountB = liquidity * reserveUsdt / totalLp;
        reserveUsdt -= amountB;
        totalLp -= liquidity;
        if (amountB > 0) IERC20(tokenB).transfer(to, amountB);
    }
}

// ══════════════════════════════════════════════════════════════════════════════
// §21  Coverage gap closers — YieldPoolCore uncovered branches
// ══════════════════════════════════════════════════════════════════════════════

contract Test_CoverageGaps is YieldPoolTest {
    // 21.1 — batchClaim with no pending reward reverts NoRewardToClaim.
    //         Covers the totalReward == 0 branch in _batchClaim (YieldPoolCore line 173).
    function test_BatchClaim_AllZeroPending_Reverts() public {
        uint256 sid = _stake(alice, 100 * ARC_UNIT);
        // No notifyReward — every _settleArcReward returns 0.
        uint256[] memory ids = new uint256[](1);
        ids[0] = sid;
        vm.prank(alice);
        vm.expectRevert(YieldPoolErrors.NoRewardToClaim.selector);
        pool.batchClaim(ids);
    }

    // 21.2 — _processEligibility fast path fires when all LP ARC is already eligible
    //         and a new calendar day has elapsed.
    //         Covers lines 204-206 (fast path lastProcessedDay update + return).
    function test_ProcessEligibility_FastPath_WhenAllArcAlreadyEligible() public {
        _activateLpMode();
        _prepareForLp(alice, 1000 * USDT_UNIT);
        _addLpStake(alice, 100 * ARC_UNIT, 1000 * USDT_UNIT);

        // Warp past the 7-day eligibility window; first notifyReward sweeps the
        // eligibility queue, making totalEligibleArc == totalLpArcContributed.
        vm.warp(block.timestamp + 8 days);
        _notify(500 * USDT_UNIT);

        uint256 lastDay = pool.lastProcessedDay();

        // Warp one more calendar day. Now: today > lastProcessedDay AND
        // totalLpArcContributed == totalEligibleArc → fast path must fire.
        vm.warp(block.timestamp + 1 days);
        _notify(200 * USDT_UNIT);

        assertGt(pool.lastProcessedDay(), lastDay, "fast path did not advance lastProcessedDay");
    }

    // 21.3 — addLiquidityAndStake with arcAmount == 0 reverts ZeroAmount.
    //         Covers the true branch of the zero-amount guard (YieldPoolCore line 252).
    function test_AddLiquidityAndStake_ZeroArc_Reverts() public {
        _activateLpMode();
        _prepareForLp(alice, 1000 * USDT_UNIT);
        vm.prank(alice);
        vm.expectRevert(YieldPoolErrors.ZeroAmount.selector);
        pool.addLiquidityAndStake(0, 1000 * USDT_UNIT, 0, 0);
    }

    // 21.4 — addLiquidityAndStake with usdtAmount == 0 reverts ZeroAmount.
    //         Covers the true branch of the zero-amount guard (YieldPoolCore line 252).
    function test_AddLiquidityAndStake_ZeroUsdt_Reverts() public {
        _activateLpMode();
        vm.prank(alice);
        vm.expectRevert(YieldPoolErrors.ZeroAmount.selector);
        pool.addLiquidityAndStake(100 * ARC_UNIT, 0, 0, 0);
    }
}

// ══════════════════════════════════════════════════════════════════════════════
// §22  Partial router — refund branches (YieldPoolCore lines 277-278)
// ══════════════════════════════════════════════════════════════════════════════

contract Test_PartialRouterCoverage is Test {
    uint256 internal constant ARC_UNIT = 1e18;
    uint256 internal constant USDT_UNIT = 1e6;

    YieldPool internal pool;
    MockARC internal arc;
    MockUSDT internal usdt;
    MockLP internal lp;

    address internal alice = makeAddr("alice");
    address internal rewarder = makeAddr("rewarder");
    address internal lpActivatorAddr = makeAddr("lpActivator");

    function setUp() public {
        arc = new MockARC();
        usdt = new MockUSDT();
        lp = new MockLP();
        MockPartialRouter partialRouter = new MockPartialRouter(address(lp));
        pool = new YieldPool(address(arc), address(usdt), rewarder, lpActivatorAddr, address(partialRouter));

        arc.mint(alice, 1_000_000 * ARC_UNIT);
        usdt.mint(alice, 1_000_000 * USDT_UNIT);

        vm.prank(alice);
        arc.approve(address(pool), type(uint256).max);
        vm.prank(alice);
        usdt.approve(address(pool), type(uint256).max);

        vm.prank(lpActivatorAddr);
        pool.activateLpMode(address(lp));
    }

    // 22.1 — When the router uses less than the provided amounts, the pool refunds
    //         the difference back to the caller.
    //         Covers the true branches of YieldPoolCore lines 277 (arcAmount > arcUsed)
    //         and 278 (usdtAmount > usdtUsed).
    function test_AddLiquidityAndStake_PartialFill_RefundsUnusedTokens() public {
        uint256 arcAmount = 100 * ARC_UNIT;
        uint256 usdtAmount = 1000 * USDT_UNIT;

        uint256 arcBefore = arc.balanceOf(alice);
        uint256 usdtBefore = usdt.balanceOf(alice);

        vm.prank(alice);
        pool.addLiquidityAndStake(arcAmount, usdtAmount, 0, 0);

        // Router consumed (amount - 1) of each; pool must refund the 1-unit remainder.
        assertEq(arcBefore - arc.balanceOf(alice), arcAmount - 1, "unused ARC not refunded");
        assertEq(usdtBefore - usdt.balanceOf(alice), usdtAmount - 1, "unused USDT not refunded");
    }
}

// ══════════════════════════════════════════════════════════════════════════════
// §23  Zero-arc router — arcContributed == 0 branch (YieldPoolCore line 466)
// ══════════════════════════════════════════════════════════════════════════════

contract Test_ZeroArcRouterCoverage is Test {
    uint256 internal constant ARC_UNIT = 1e18;
    uint256 internal constant USDT_UNIT = 1e6;

    YieldPool internal pool;
    MockARC internal arc;
    MockUSDT internal usdt;
    MockLP internal lp;

    address internal alice = makeAddr("alice");
    address internal rewarder = makeAddr("rewarder");
    address internal lpActivatorAddr = makeAddr("lpActivator");

    function setUp() public {
        arc = new MockARC();
        usdt = new MockUSDT();
        lp = new MockLP();
        MockZeroArcRouter zeroRouter = new MockZeroArcRouter(address(lp));
        pool = new YieldPool(address(arc), address(usdt), rewarder, lpActivatorAddr, address(zeroRouter));

        arc.mint(alice, 1_000_000 * ARC_UNIT);
        usdt.mint(alice, 1_000_000 * USDT_UNIT);
        usdt.mint(rewarder, 1_000_000 * USDT_UNIT);

        vm.prank(alice);
        arc.approve(address(pool), type(uint256).max);
        vm.prank(alice);
        usdt.approve(address(pool), type(uint256).max);
        vm.prank(rewarder);
        usdt.approve(address(pool), type(uint256).max);

        vm.prank(lpActivatorAddr);
        pool.activateLpMode(address(lp));
    }

    // 23.1 — When the router returns arcUsed == 0 the LP stake is recorded with
    //         arcContributed == 0, and pendingLpReward short-circuits to 0.
    //         Covers the arcContributed == 0 branch of _pendingLpReward (line 466).
    function test_PendingLpReward_ZeroArcContributed_ReturnsZero() public {
        uint256 arcAmount = 100 * ARC_UNIT;
        uint256 usdtAmount = 1000 * USDT_UNIT;

        uint256 arcBefore = arc.balanceOf(alice);

        vm.prank(alice);
        pool.addLiquidityAndStake(arcAmount, usdtAmount, 0, 0);
        uint256 lpId = pool.nextLpStakeId() - 1;

        (, uint256 arcContributed,,,,,) = pool.lpStakes(lpId);
        assertEq(arcContributed, 0, "arcContributed should be 0 (zero-arc router)");

        // Pool pulls arcAmount but router uses 0; all ARC is refunded.
        assertEq(arc.balanceOf(alice), arcBefore, "ARC should be fully refunded");

        // Warp and notify so _processEligibility runs (but 0 ARC is eligible).
        vm.warp(block.timestamp + 8 days);
        vm.prank(rewarder);
        pool.notifyReward(500 * USDT_UNIT);

        // pendingLpReward must return 0 because arcContributed == 0.
        assertEq(pool.pendingLpReward(lpId), 0, "pending should be 0 for zero-arc stake");
    }
}
