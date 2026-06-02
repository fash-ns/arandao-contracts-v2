# YieldPool — Test Cases

All tests live in `test/YieldPool/YieldPool.t.sol`.

---

## §1 Core Correctness

| Test | Description |
|------|-------------|
| `test_SingleUser_FullReward` | A single staker receives the entire reward exactly; pending resets to zero after claim. |
| `test_MultiUser_ProportionalDistribution` | Three stakers (50 / 30 / 20 ARC) each receive their exact proportional share of a 1 000 USDT reward. |
| `test_SequentialRewards_Accumulate` | Two back-to-back `notifyReward` calls accumulate without resetting; a single claim pays the full combined amount. |

---

## §2 RewardDebt Correctness

| Test | Description |
|------|-------------|
| `test_NodoubleClaim` | Claiming twice with no new reward reverts with `NoRewardToClaim` on the second call. |
| `test_PartialClaim_ThenNewReward` | Each reward epoch is paid exactly once; a second claim after a new `notifyReward` pays only the delta. |

---

## §3 Mid-Entry User

| Test | Description |
|------|-------------|
| `test_LateJoiner_NoPastRewards` | A staker who joins after a reward is distributed earns nothing from that past epoch. |
| `test_JoinBeforeReward_EarnsOnlyFromThatPoint` | A staker who joins before a reward (same block as an earlier staker) earns correctly from that reward forward. |
| `test_RewardDebt_InitialisedCorrectly` | A late joiner's `rewardDebt` is initialised to the current accumulator snapshot, producing zero pending reward immediately after staking. |

---

## §4 totalStaked Manipulation

| Test | Description |
|------|-------------|
| `test_NewStake_MidCycle_DoesNotDilutePast` | A large stake placed after a reward does not retroactively dilute earlier stakers' rewards. |
| `test_Unstake_StopsAccrual` | Unstaking atomically returns ARC + accrued USDT; subsequent rewards are not received by the closed position. |

---

## §5 Zero-Staker Edge Cases

| Test | Description |
|------|-------------|
| `test_RewardWithNoStakers_Queued` | Reward sent when no one is staked goes into `queuedRewards`; the accumulator stays at zero. |
| `test_QueuedRewards_DistributedOnNextNotify` | Queued rewards do not leak to a staker who joined before the flush; they are distributed together with the next `notifyReward` call. |
| `test_MultipleQueuedDeposits_FlushTogether` | Multiple rewards queued with no stakers all flush together on the next `notifyReward` once a staker exists. |
| `test_NoRevertOnZeroStake_Notify` | Calling `notifyReward` when `totalStaked == 0` does not revert (no division-by-zero). |

---

## §6 Precision & Rounding

| Test | Description |
|------|-------------|
| `test_SmallReward_RoundingDirection` | Sum of all stakers' pending rewards never exceeds the injected amount (floor division only); dust loss is ≤ 3 wei. |
| `test_LargeAmounts_NoOverflow` | 100 billion ARC staked with a 10 million USDT reward does not overflow and pays the correct amount. |
| `test_AccRewardPerShare_Monotonic` | `accRewardPerShare` strictly increases with each successive `notifyReward` call. |

---

## §7 Multiple Stake Positions Per User

| Test | Description |
|------|-------------|
| `test_TwoPositions_IndependentAccrual` | Two positions opened by the same user accumulate rewards independently, proportional to their sizes. |
| `test_ClaimOnePosition_OtherUnaffected` | Claiming one stake ID does not alter the pending reward of a sibling position. |
| `test_BatchClaim_AllPositions` | `batchClaim` collects rewards from multiple positions in a single USDT transfer. |
| `test_BatchClaim_DuplicateId_NoDoublePay` | Passing the same stake ID twice in `batchClaim` pays it only once. |
| `test_GetUserStakeIds_IncludesInactive` | `getUserStakeIds` returns all IDs regardless of whether positions have been unstaked. |

---

## §8 Claim Timing

| Test | Description |
|------|-------------|
| `test_NewReward_BetweenViewAndClaim` | A reward injected between an off-chain `pendingReward` read and the actual `claim` is included in the payout (no stale-view issue). |

---

## §9 Attack-Style Tests

| Test | Description |
|------|-------------|
| `test_DirectDonation_CannotManipulateAcc` | Directly sending USDT to the pool does not change `accRewardPerShare` or any user's pending reward. |
| `test_LateInflationAttack_DoesNotDilutePast` | A massive stake placed after a reward does not dilute past recipients' pending balance. |
| `test_FlashStake_ProportionalNotFree` | A same-block stake → reward → unstake sequence earns only the proportional share; it cannot steal the full reward. |
| `test_AccessControl_NotifyReward_Restricted` | Any address other than `rewarder` is rejected by `notifyReward` with `NotRewarder`. |
| `test_Ownership_CannotUnstakeOthers` | Calling `unstake` with another user's stake ID reverts with `NotStakeOwner`. |
| `test_Ownership_CannotClaimOthers` | Calling `claim` with another user's stake ID reverts with `NotStakeOwner`. |

---

## §10 Invariant / Fuzz Tests

| Test | Description |
|------|-------------|
| `testFuzz_SingleStaker_GetsFullReward` | A single staker always receives the full injected reward (within 1 wei of floor-division dust), for any stake amount and reward amount. |
| `testFuzz_TwoStakers_SumEqualsInjected` | The combined pending rewards of two stakers never exceed the injected amount and lose at most 2 wei total. |
| `testFuzz_PendingNeverNegative` | After claim + new reward, `pendingReward` never underflows (Solidity ≥ 0.8 guarantees, verified across fuzz space). |
| `testFuzz_AccRewardPerShare_Monotonic` | `accRewardPerShare` never decreases across five consecutive `notifyReward` calls with random amounts. |
| `testFuzz_ContractBalance_CoversAllPending` | The pool's USDT balance always covers the sum of all pending rewards for any two stakers and any reward amount. |

---

## §11 Full Lifecycle Integration

| Test | Description |
|------|-------------|
| `test_FullLifecycle` | End-to-end scenario: three stakers join, rewards are distributed and claimed, a fourth staker joins mid-cycle, a second reward epoch is run, one staker exits, a third reward is injected, and final conservation is verified across all three epochs (total in = total out). |

---

## §12 Error & Constructor Validation

| Test | Description |
|------|-------------|
| `test_Constructor_ZeroAddress_Reverts` | Passing `address(0)` for any of the five constructor parameters reverts with `ZeroAddress`. |
| `test_Stake_ZeroAmount_Reverts` | `stake(0)` reverts with `ZeroAmount`. |
| `test_NotifyReward_ZeroAmount_Reverts` | `notifyReward(0)` reverts with `ZeroAmount`. |
| `test_Claim_InactiveStake_Reverts` | Claiming a stake that has already been unstaked reverts with `StakeNotActive`. |
| `test_Unstake_InactiveStake_Reverts` | Unstaking an already-closed position reverts with `StakeNotActive`. |
| `test_BatchClaim_EmptyArray_Reverts` | `batchClaim([])` reverts with `EmptyStakeIds`. |

---

## §13 Frozen Rewards (USDT Paused / Blacklisted)

| Test | Description |
|------|-------------|
| `test_Unstake_UsdtReverts_ArcReturnedRewardFrozen` | When USDT transfer reverts on unstake, ARC is still returned and the reward is stored in `frozenRewards`; `RewardFrozen` event is emitted. |
| `test_Unstake_UsdtReturnsFalse_ArcReturnedRewardFrozen` | Same as above when USDT `transfer` returns `false` instead of reverting. |
| `test_ClaimFrozenRewards_NoBalance_Reverts` | `claimFrozenRewards` with no frozen balance reverts with `NoFrozenRewards`. |
| `test_ClaimFrozenRewards_AfterUnfreeze` | After USDT is unpaused, `claimFrozenRewards` pays out the full frozen amount and clears the mapping. |
| `test_ClaimFrozenRewards_NoDoubleClaim` | Calling `claimFrozenRewards` twice reverts on the second call once the balance is cleared. |
| `test_MultipleUnstakes_FrozenRewardsAccumulate` | Rewards from multiple consecutive frozen unstakes accumulate correctly in `frozenRewards`. |
| `test_Unstake_ZeroReward_NoFrozenEntry` | Unstaking a position with zero pending reward while USDT is frozen creates no entry in `frozenRewards`. |
| `test_FrozenRewards_PerUser_Isolated` | Freezing one user's reward does not affect another user's ability to unstake and receive USDT normally. |

---

## §14 batchUnstake

| Test | Description |
|------|-------------|
| `test_BatchUnstake_EmptyArray_Reverts` | `batchUnstake([])` reverts with `EmptyStakeIds`. |
| `test_BatchUnstake_TooLarge_Reverts` | An array of 21 IDs reverts with `BatchTooLarge`. |
| `test_BatchUnstake_ExactlyMaxLen_Accepted` | Exactly 20 positions is accepted at the boundary and all ARC is returned. |
| `test_BatchUnstake_InactiveStake_Reverts` | Including an inactive ID in the batch reverts entirely with `StakeNotActive`; active positions remain untouched. |
| `test_BatchUnstake_NotOwner_Reverts` | Including another user's stake ID in the batch reverts with `NotStakeOwner`. |
| `test_BatchUnstake_FullBatch_ArcAndUsdtReturned` | Three positions are closed in one call; correct ARC and USDT totals are transferred and all positions become inactive. |
| `test_BatchUnstake_TotalStaked_ReducedCorrectly` | `totalStaked` is decremented by the exact ARC removed by the batch. |
| `test_BatchUnstake_NoReward_OnlyArcReturned` | With no reward injected, only ARC is returned and USDT balance is unchanged. |
| `test_BatchUnstake_RewardsMatchSingleUnstake` | Rewards paid by `batchUnstake` match the sum of what individual `unstake` calls would have paid. |
| `test_BatchUnstake_UsdtFrozen_AllRewardsFrozen` | When USDT is frozen for all positions in a batch, all rewards land in `frozenRewards` and all ARC is still returned. |
| `testFuzz_BatchUnstake_ConservesTokens` | For any batch size 1–20 and any reward amount, total ARC returned equals total staked and total USDT returned equals reward (within floor-division dust of `n` wei). |

---

## §15 LP Mode Switch — Access Control & State Machine

| Test | Description |
|------|-------------|
| `test_ActivateLpMode_AccessControl` | Only `lpActivator` can call `activateLpMode`; any other caller reverts with `NotLpActivator`. |
| `test_ActivateLpMode_OnlyOnce` | Calling `activateLpMode` a second time reverts with `LpModeAlreadyActive`. |
| `test_ActivateLpMode_InvalidLpToken` | Passing `address(0)`, the ARC address, or the USDT address as LP token reverts with `InvalidLpToken`. |
| `test_Stake_BlockedAfterLpMode` | After LP mode is activated, `stake()` permanently reverts with `ArcStakingDisabled`. |
| `test_AddLiquidityAndStake_RevertsBeforeLpMode` | `addLiquidityAndStake` reverts with `LpModeNotActive` while the pool is still in ARC-only mode. |
| `test_ActivateLpMode_StateCorrect` | After activation, `lpModeActive` is `true` and `lpToken` is set to the provided address. |

---

## §16 ARC Stakers During and After LP Mode Transition

| Test | Description |
|------|-------------|
| `test_ArcStakers_CanUnstakeAfterSwitch` | Existing ARC stakers can still call `unstake` and receive their ARC and accrued USDT after LP mode is activated. |
| `test_ArcStakers_NoNewRewardsAfterSwitch` | After the switch, `notifyReward` feeds the LP accumulator; the ARC `accRewardPerShare` is frozen and existing ARC positions earn nothing new. |
| `test_ArcStakers_CanClaimAfterSwitch` | ARC stakers can still call `claim` to collect rewards that accrued before the switch. |
| `test_AfterSwitch_NotifyReward_QueuesWhenNoLpStakers` | `notifyReward` with no LP stakers goes into `queuedLpRewards` and leaves the LP accumulator at zero. |

---

## §17 LP Staking — 7-Day Minimum Eligibility

| Test | Description |
|------|-------------|
| `test_LpStake_StateCorrect` | `addLiquidityAndStake` records the correct owner, LP amount, ARC contribution, `eligibleDay`, `active=true`, and `enrolled=false`. |
| `test_LpStake_LpTokensHeldByPool` | LP tokens are held by the pool after staking; the user holds none. |
| `test_LpStake_ClaimBefore7Days_Reverts` | `claimLpReward` before the 7-day window reverts with `StakeNotYetEligible`. |
| `test_LpStake_SingleStaker_EarnsFullRewardAfterMinDuration` | A single LP staker past the 7-day threshold receives the full reward; pending resets to zero after claim. |
| `test_LpStake_PreEligibilityNotify_QueuedThenFlushed` | Rewards notified before any eligible ARC is queued; once a staker becomes eligible the queued amount flushes together with the next reward. |
| `test_LpStake_TwoStakers_ProportionalAfterMinDuration` | Two LP stakers past 7 days split rewards proportionally by ARC contributed. |
| `test_LpStake_LateStaker_MissesEarlyEpoch` | A staker who joins after epoch 1 has already run earns nothing from that epoch; they earn proportionally from epoch 2 onwards. |
| `test_ClaimLpReward_EnrollsAndResets` | The first successful `claimLpReward` marks the stake as `enrolled=true` and resets pending to zero. |
| `test_ClaimLpReward_EligibleButNoEpoch_Reverts` | Past the 7-day window but with no `notifyReward` yet, `claimLpReward` reverts with `NoRewardToClaim`. |
| `test_ClaimLpReward_WrongOwner_Reverts` | Calling `claimLpReward` with another user's LP stake ID reverts with `NotLpStakeOwner`. |
| `test_ClaimLpReward_NotActive_Reverts` | Claiming a cancelled LP stake reverts with `LpStakeNotActive`. |

---

## §18 LP Stake Cancellation

| Test | Description |
|------|-------------|
| `test_CancelLpStake_BeforeEligible_ReturnsTokensNoReward` | Cancelling within the 7-day window returns ARC and USDT liquidity; no reward is paid. |
| `test_CancelLpStake_BeforeEligible_RemovesFromQueue` | Cancelling before eligibility removes the ARC contribution from `eligibilityByDay` and zeros `totalLpArcContributed`. |
| `test_CancelLpStake_AfterEligible_ReturnsTokensAndReward` | Cancelling after the 7-day window returns ARC and USDT liquidity plus the accrued reward. |
| `test_CancelLpStake_AfterEligible_RemovesFromEligiblePool` | Cancelling after eligibility reduces `totalEligibleArc` to zero. |
| `test_CancelLpStake_InactiveAfterCancel` | A cancelled stake cannot be cancelled a second time; reverts with `LpStakeNotActive`. |
| `test_CancelLpStake_WrongOwner_Reverts` | Calling `cancelLpStake` for another user's ID reverts with `NotLpStakeOwner`. |
| `test_CancelLpStake_PeerUnaffected` | Cancelling one user's LP stake does not alter another user's pending LP reward. |
| `test_GetUserLpStakeIds_IncludesCancelled` | `getUserLpStakeIds` returns all IDs including cancelled ones. |

---

## §18b cancelLpStake — Frozen USDT Reward Path

| Test | Description |
|------|-------------|
| `test_CancelLpStake_UsdtReverts_LpReturnedRewardFrozen` | When USDT transfer from the pool reverts (blacklisted), liquidity is returned via the router and the reward is stored in `frozenRewards`; `RewardFrozen` is emitted. |
| `test_CancelLpStake_UsdtReturnsFalse_RewardFrozen` | Same as above when `transfer` returns `false`. |
| `test_CancelLpStake_FrozenReward_ClaimableAfterUnfreeze` | After the pool address is removed from the blacklist, `claimFrozenRewards` recovers the full reward and clears the mapping. |
| `test_CancelLpStake_NoReward_FrozenMapUntouched` | Cancelling before eligibility with USDT frozen creates no `frozenRewards` entry (no reward to transfer). |
| `test_CancelLpStake_NoLpRewardClaimedEventOnFreeze` | When a reward is frozen, `LpRewardClaimed` is NOT emitted; only `RewardFrozen` fires. |

---

## §19 batchClaimLpReward

| Test | Description |
|------|-------------|
| `test_BatchClaimLpReward_EmptyArray_Reverts` | Empty array reverts with `EmptyStakeIds`. |
| `test_BatchClaimLpReward_TooLarge_Reverts` | Array of 21 IDs reverts with `BatchTooLarge`. |
| `test_BatchClaimLpReward_NotActive_Reverts` | Including a cancelled stake ID reverts with `LpStakeNotActive`. |
| `test_BatchClaimLpReward_WrongOwner_Reverts` | Including another user's LP stake ID reverts with `NotLpStakeOwner`. |
| `test_BatchClaimLpReward_NotEligible_Reverts` | Including a stake that has not yet passed its 7-day window reverts with `StakeNotYetEligible`. |
| `test_BatchClaimLpReward_ZeroReward_Reverts` | Eligible stake with zero pending reward reverts with `NoRewardToClaim`. |
| `test_BatchClaimLpReward_TwoStakes_PaidTogether` | Two LP stakes are settled and paid in a single USDT transfer; both pending balances reset. |
| `test_BatchClaimLpReward_DuplicateId_NoDoublePay` | A duplicate ID in the array is settled twice but pays only once (second settle is 0). |
| `test_BatchClaimLpReward_MultiEpoch_OnlyDeltaPaid` | After claiming epoch 1 manually, `batchClaimLpReward` pays only the epoch 2 delta. |

---

## §20 batchCancelLpStake

| Test | Description |
|------|-------------|
| `test_BatchCancelLpStake_EmptyArray_Reverts` | Empty array reverts with `EmptyStakeIds`. |
| `test_BatchCancelLpStake_TooLarge_Reverts` | Array of 21 IDs reverts with `BatchTooLarge`. |
| `test_BatchCancelLpStake_LengthMismatch_Reverts` | Mismatched `ids`, `amountsAMin`, `amountsBMin` array lengths revert with `ArrayLengthMismatch`. |
| `test_BatchCancelLpStake_WrongOwner_Reverts` | Another user's stake ID in the batch reverts with `NotLpStakeOwner`. |
| `test_BatchCancelLpStake_InactiveStake_Reverts` | An already-cancelled stake ID reverts with `LpStakeNotActive`. |
| `test_BatchCancelLpStake_BeforeEligible_NoReward` | Batch cancellation before the eligibility window returns full liquidity and removes ARC from the queue; no reward is paid. |
| `test_BatchCancelLpStake_AfterEligible_ReturnsTokensAndReward` | Batch cancellation after eligibility returns full liquidity plus accrued reward; `totalEligibleArc` is zeroed. |
| `test_BatchCancelLpStake_TwoStakes_CombinedReward` | Two eligible stakes cancelled together return combined ARC and USDT reward in a single operation. |
| `test_BatchCancelLpStake_MixedEligibility` | A batch containing one eligible and one ineligible stake handles each correctly: reward paid for the eligible, only liquidity returned for the other. |
| `test_BatchCancelLpStake_PeerUnaffected` | Batch-cancelling one user's stakes does not alter another user's pending LP reward. |
