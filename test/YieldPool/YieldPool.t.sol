// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {Test} from "forge-std/Test.sol";
import {YieldPool} from "../../src/YieldPool/YieldPool.sol";
import {YieldPoolErrors} from "../../src/YieldPool/lib/YieldPoolErrors.sol";
import {YieldPoolEvents} from "../../src/YieldPool/lib/YieldPoolEvents.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

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

    // ── actors ──
    address internal alice = makeAddr("alice");
    address internal bob = makeAddr("bob");
    address internal charlie = makeAddr("charlie");
    address internal dave = makeAddr("dave");
    address internal rewarder = makeAddr("rewarder");
    address internal attacker = makeAddr("attacker");

    // ─── Setup ────────────────────────────────────────────────────────────────

    function setUp() public virtual {
        arc = new MockARC();
        usdt = new MockUSDT();
        pool = new YieldPool(address(arc), address(usdt), rewarder);

        // Fund users with ARC
        arc.mint(alice, 1_000_000 * ARC_UNIT);
        arc.mint(bob, 1_000_000 * ARC_UNIT);
        arc.mint(charlie, 1_000_000 * ARC_UNIT);
        arc.mint(dave, 1_000_000 * ARC_UNIT);
        arc.mint(attacker, 1_000_000 * ARC_UNIT);

        // Fund rewarder with USDT
        usdt.mint(rewarder, 10_000_000 * USDT_UNIT);

        // Pre-approve pool
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

    function transfer(address to, uint256 amount) public override returns (bool) {
        if (transferReverts) revert("USDT: frozen");
        if (transferReturnsFalse) return false;
        return super.transfer(to, amount);
    }
}

// ══════════════════════════════════════════════════════════════════════════════
// §12  Error & constructor validation
// ══════════════════════════════════════════════════════════════════════════════

contract Test_ErrorsAndConstructor is YieldPoolTest {
    // Constructor rejects zero addresses
    function test_Constructor_ZeroAddress_Reverts() public {
        vm.expectRevert(YieldPoolErrors.ZeroAddress.selector);
        new YieldPool(address(0), address(usdt), rewarder);

        vm.expectRevert(YieldPoolErrors.ZeroAddress.selector);
        new YieldPool(address(arc), address(0), rewarder);

        vm.expectRevert(YieldPoolErrors.ZeroAddress.selector);
        new YieldPool(address(arc), address(usdt), address(0));
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

    function setUp() public {
        arc = new MockARC();
        usdt = new MockFreezableUSDT();
        pool = new YieldPool(address(arc), address(usdt), rewarder);

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
