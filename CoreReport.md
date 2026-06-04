# Security & Logic Review — `contracts/core/Core.sol` (DNMCore)

**Scope:** `Core.sol` and all of its imports: `Users.sol`, `Sellers.sol`, `SellerLib.sol`, `Orders.sol`, `OrderLib.sol`, `UserLib.sol`, `HelpersLib.sol`, `Finance.sol`, `CalculationLogic.sol`, `CoreLib.sol`, `SecurityGuard.sol`, `SecurityGuardLib.sol`, `IFastValue.sol`, `IARC.sol`, `IYieldPool.sol`, `ITwapOracle.sol`.

**Summary:** The contract is well-structured and uses `ReentrancyGuard`, `SafeERC20`, and custom errors. However, there are several real bugs and security/economic concerns ranging from a likely-blocking arithmetic underflow in the weekly ARC mint path, a reentrancy/CEI violation, an unbounded-trust external write into user storage, a `uint8` loop counter that can DoS large batches, and missing invariant maintenance during migration.

Severity legend: **Critical** (funds loss / protocol break), **High** (serious correctness/trust), **Medium** (conditional/operational), **Low** (hardening), **Info** (style/clarity).

---

## Critical

### C-1. Underflow in `_mintWeeklyArc`: `pastWeekBv - totalCommissionEarned` can revert and permanently block weekly ARC minting

`Finance.sol`:

```105:105:contracts/core/Finance.sol
    uint256 dexTransferAmount = pastWeekBv - totalCommissionEarned;
```

- `pastWeekBv` is **one week's** BV × 80% (`totalWeeklyBv[pastWeekNumber] * 80 / 100`).
- `totalCommissionEarned` is a **global, cumulative** counter of all unwithdrawn commission across *all* weeks (`Finance.sol` L23, incremented in `_calculateCommissionForPeriod` L425 and only reduced on `withdrawCommission`).

These two quantities are unrelated in magnitude. As soon as accumulated outstanding commission exceeds a single week's 80%-of-BV (very common once the network matures, or simply on any low-volume week), the subtraction underflows and reverts on Solidity 0.8.x. Because `mintWeeklyARC()` is the gateway used by `calculateNetworkerWeeklyARC`, `calculateUserWeeklyArc`, and `calculateSellerWeeklyArc` (they call `mintWeeklyARC()` when `passedWeekNumber > arcMintWeekNumber`), **a revert here can block the entire weekly ARC distribution for everyone.**

**Fix:** Clamp the subtraction and use the correct per-week figure. Either:
```solidity
uint256 weekCommission = totalCommissionEarnedByWeek[pastWeekNumber];
uint256 dexTransferAmount = pastWeekBv > weekCommission ? pastWeekBv - weekCommission : 0;
```
or, if the intent really is "remaining global pool," guard it:
```solidity
uint256 dexTransferAmount = pastWeekBv > totalCommissionEarned ? pastWeekBv - totalCommissionEarned : 0;
```
Confirm the economic intent with the spec — using the global `totalCommissionEarned` against one week's BV looks semantically wrong regardless of the underflow.

---

## High

### H-1. Reentrancy / CEI violation in `_mintWeeklyArc` (state updated *after* external call)

```104:122:contracts/core/Finance.sol
    IERC20 paymentToken = IERC20(paymentTokenAddress);
    uint256 dexTransferAmount = pastWeekBv - totalCommissionEarned;
    ...
    if (dexTransferAmount > 0) {
      _approvePaymentToken(yieldPoolAddress, dexTransferAmount);
      yieldPoolContract.notifyReward(dexTransferAmount);   // external call
    }

    lastWeekArcMintAmount = mintAmount;                     // state updated AFTER
    arcMintWeekNumber = pastWeekNumber;                     // the dedup guard is set here
    emit weeklyArcMinted(pastWeekNumber, mintAmount);
```

`mintWeeklyARC()` in `Core.sol` is **`public` and NOT `nonReentrant`**:

```491:491:contracts/core/Core.sol
  function mintWeeklyARC() public {
```

The dedup guard `arcMintWeekNumber < pastWeekNumber` (`Finance.sol` L83-86) is only updated *after* the external `notifyReward` call. If `yieldPoolAddress` (set by dev via `setAddresses`) is malicious or compromised, its `notifyReward` callback can re-enter `mintWeeklyARC()` before `arcMintWeekNumber` is updated, passing the guard again and **minting ARC multiple times for the same week**. The current production `YieldPool.notifyReward` is itself `nonReentrant`, which mitigates this *today*, but Core must not rely on the callee's guard.

**Fix:** Apply Checks-Effects-Interactions — set `arcMintWeekNumber = pastWeekNumber;` and `lastWeekArcMintAmount = mintAmount;` *before* the external `notifyReward` call, and/or add `nonReentrant` to `mintWeeklyARC()`. (Note: the other ARC functions are `nonReentrant`, but they call `mintWeeklyARC()` internally, so adding `nonReentrant` to `mintWeeklyARC` directly would double-enter the guard from those paths — restructure so the public entrypoint holds the guard and an internal `_mintWeeklyArcGuarded` is shared, or simply rely on CEI ordering plus a guard only on the public path.)

### H-2. FastValue can overwrite the *entire* user struct in storage

```412:423:contracts/core/Core.sol
    if (user.superNodeTotalSteps > 1) {
      IFastValue fv = IFastValue(fvAddress);
      uint256 month = HelpersLib.getMonth(lastOrderTimestamp);
      users[userId] = fv.checkUserAuthorityForFvEntrance(
        user, userId, _getMinBv(), month, lastOrderTimestamp
      );
    }
```

`users[userId]` is fully replaced by a `UserLib.User` returned from an external contract. This means `FastValue` controls **every** field of the user — `bv`, `withdrawableCommission`, `childrenBv`, `path`, `parentId`, `position`, `active`, etc. A bug or compromise in `FastValue` (whose address is dev-settable via `setAddresses`) can corrupt tree topology, zero out balances, or inflate `withdrawableCommission`. Even with a benign `FastValue`, returning a struct that does not faithfully preserve `path`/`childrenBv` would silently destroy MLM accounting.

**Fix:** Do not let an external contract return a full `User`. Have `FastValue` return only the specific FV-related fields it is allowed to change (e.g. `fvEntranceMonth`, `fvEntranceShare`, `minBvForFv`) and apply them field-by-field in Core:
```solidity
(uint256 fvMonth, uint8 fvShare, uint256 minBvForFv) = fv.checkUserAuthorityForFvEntrance(...);
user.fvEntranceMonth = fvMonth;
user.fvEntranceShare = fvShare;
user.minBvForFv = minBvForFv;
```
The same pattern should be re-examined for `registerUserFvFromPurchase` (passes a `User memory` — verify FV cannot use it to make state-changing decisions that contradict Core).

---

## Medium

### M-1. `uint8` loop counter in `calculateOrders` truncates / DoSes large batches

```234:238:contracts/core/Core.sol
    uint16 orderIdsLen = uint16(orderIds.length);
    uint256 lastOrderId = user.lastCalculatedOrder;
    for (uint8 i = 0; i < orderIdsLen; i++) {
```

- The loop index `i` is `uint8` but the bound `orderIdsLen` is `uint16`. If `orderIds.length >= 256`, when `i == 255` the body runs, then `i++` overflows and **reverts** (0.8.x checked arithmetic). Batches of ≥256 orders can never be processed.
- `uint16(orderIds.length)` also silently truncates if length > 65535; `lastCalculatedOrder` would then be set to a truncated index `orderIds[orderIdsLen-1]`, skipping orders.

**Fix:** Use `uint256 i` and iterate against `orderIds.length` directly (no `uint16` cast):
```solidity
uint256 len = orderIds.length;
for (uint256 i = 0; i < len; i++) { ... }
... orderIds[len - 1] ...
```

### M-2. `migrateUser` does not set `positionTaken`, allowing later position collisions / tree corruption

```89:103:contracts/core/Core.sol
  function migrateUser(UserLib.User[] calldata data) external onlyDevMode {
    ...
      users[nextUserId] = data[i];
      addressToUserId[data[i].userAddress] = nextUserId;
      ...
      nextUserId += 1;
```

Migrated users carry a `parentId`/`position`, but `positionTaken[parentId][position]` is never set. After migration, `_getOrCreateUser` (`Users.sol` L127) only checks `positionTaken`, so a newly registered user can claim a position **already occupied by a migrated child**, producing two children at the same position and corrupting `path`/subtree logic. It also never validates `position <= 3` or parent existence for migrated rows.

**Fix:** During migration set `positionTaken[data[i].parentId][data[i].position] = true;` (when `parentId != 0`), and validate `position <= 3`. Consider also asserting the provided `path` matches the parent's path + position encoding.

### M-3. ARC distribution uses single mutable globals (`totalArcWeeklySteps`, `lastWeekArcMintAmount`) — cross-week race

`totalArcWeeklySteps` (Core L46/505) and `lastWeekArcMintAmount` (Finance) are single storage slots overwritten each time `mintWeeklyARC` runs. `calculateNetworkerWeeklyARC` (L557-559) and `calculateUserWeeklyArc`/`calculateSellerWeeklyArc` compute each claimant's share from these *latest* globals, but claims are keyed to a specific `passedWeekNumber`. If `mintWeeklyARC` advances to a newer week before some claimants withdraw the prior week, those claimants compute shares against the **wrong week's** step total and mint amount, over- or under-paying ARC.

**Fix:** Key these values per week, e.g. `mapping(uint256 => uint256) weeklyArcSteps;` and `mapping(uint256 => uint256) weeklyArcMintAmount;`, and index by the `passedWeekNumber` being claimed rather than reading a single global.

### M-4. ARC mint amount manipulable by donating ARC to the contract

```66:78:contracts/core/Finance.sol
    uint256 currentExcessArcBalance = arcContract.balanceOf(address(this));
    uint256 totalSupply = arcContract.totalSupply();
    uint256 adjustedSupply = totalSupply - currentExcessArcBalance;
    ...
    uint256 p = ((((pastWeekTotalBv * 397) / 1000) + ((priceFromVault * totalSupply) / 1 ether)) * 1 ether) / adjustedSupply;
    mintAmount = (((pastWeekTotalBv * 234) / 1000) * 1 ether) / p;
```

`balanceOf(address(this))` is used as "excess" ARC and subtracted from supply. Anyone can transfer ARC to the Core contract to inflate `currentExcessArcBalance`, shrinking `adjustedSupply`, raising price `p`, and thus shrinking `mintAmount` — and in `_mintWeeklyArc`, a large balance means `mintAmount > currentExcessArcBalance` is false so **nothing new is minted** while the donated balance is treated as the week's mint. This lets an outsider grief the ARC issuance schedule, and `mintAmount` becomes path-dependent on transient balance.

**Fix:** Track owed/issued ARC with an internal accounting variable rather than `balanceOf(this)`, or snapshot/segregate distributable ARC so external transfers cannot influence the formula.

### M-5. Week-0 / pre-offset underflows

`HelpersLib.getWeekOfTs(block.timestamp) - 1` is used in `mintWeeklyARC` (L497), `calculateNetworkerWeeklyARC` (L526), `calculateUserWeeklyArc` (L575), `calculateSellerWeeklyArc` (L604). During the first week after `offset` (or any time `getWeekOfTs == 0`), this underflows and reverts. Similarly `_mintWeeklyArc` (Finance L82). Functions are simply unusable in week 0; ensure off-chain scheduling never calls them then, or guard with `require(week >= 1)` with a clear message.

### M-6. `calculateOrders` is not `nonReentrant` despite an external FV call

`calculateOrders` (L221, `onlyManager`) calls `FastValue.checkUserAuthorityForFvEntrance` (via `_calculateCommissionForPeriod` L416), which (per H-2) also writes `users[userId]`. It is `onlyManager` (trusted) but lacks `nonReentrant`. Combined with H-2 this is an avenue for reentrant state manipulation if FV is compromised. Add `nonReentrant` defensively.

---

## Low

### L-1. `lastOrderId` local variable shadows `Orders.lastOrderId` state

```236:236:contracts/core/Core.sol
    uint256 lastOrderId = user.lastCalculatedOrder;
```

This local shadows the inherited `Orders.lastOrderId` storage variable, which is confusing and error-prone (and triggers a compiler warning). Rename to e.g. `lastProcessedOrderId`.

### L-2. `withdrawCommission` masks accounting inconsistency

```473:477:contracts/core/Core.sol
    if (totalCommissionEarned > amount) {
      totalCommissionEarned -= amount;
    } else {
      totalCommissionEarned = 0;
    }
```

Under correct accounting `amount <= user.withdrawableCommission <= totalCommissionEarned`, so the `else` branch silently zeroing the global indicates an invariant break rather than handling it. Prefer `require(totalCommissionEarned >= amount)` (or fix the root cause) so accounting bugs surface instead of being hidden — especially since `totalCommissionEarned` feeds C-1's calculation.

### L-3. `_isSubTree` can underflow `directChildPos - 1`

```346:347:contracts/core/Users.sol
    uint8 directChildPos = _getPathByte(candidate.path, rootPathLength);
    return (true, directChildPos - 1);
```

Path bytes are stored as `position + 1` (1–4). If `_getPathByte` ever returns `0` (e.g., malformed/migrated path, or `bytes32Index >= path.length`), `0 - 1` underflows and reverts. For migrated users with externally-supplied `path`, this is reachable. Validate `directChildPos != 0` (revert with a clear error) before subtracting.

### L-4. `_getMinBv()` / `_getMaxSteps()` etc. mutate state on read

`CalculationLogic` getters (`_getMinBv`, `_getMaxSteps`, `_getBvBalance`, `_getCommissionPerStep`) lazily mutate the parameter the first time weekly mode is active. This couples "read" with a one-time write and makes them non-`view`. It works but is surprising; consider migrating to explicit parameters set once in `_activateWeeklyCalculation`.

### L-5. Missing `require` messages / validation

- `mintArc` (L109): `require(to.length == amounts.length)` has no message.
- `setAddresses` does not validate non-zero addresses; if `fvAddress`/`twapAddress`/`yieldPoolAddress` are left zero, `createOrder` and ARC minting revert on external calls to `address(0)`.
- `_getOrCreateUser` migrated branch (`Users.sol` L132-133): `users[parentId].bv - users[parentId].bvOnBridgeTime` underflows if `bvOnBridgeTime > bv`; add a guard or `min`.

---

## Informational / Design notes

### I-1. Systemic solvency risk (economic, not a code bug)
Per order, only 80% of BV is retained in Core (20% is sent to FastValue, L193-195), yet commission accrues to potentially many ancestors along the binary tree (`_calculateCommissionForPeriod`, ~6% per matched step per qualifying ancestor). Aggregate commission across the tree can exceed retained funds, leaving `withdrawCommission` to fail on the balance check (L481-484). This is inherent to binary MLM payout structures; ensure the spec's caps (`maxSteps`, flush-outs, `bvBalance`) keep total payout ≤ inflows, and document the dependence on ARC/Dex inflows for solvency.

### I-2. Centralization
- `onlyDevMode` (`SecurityGuard`) lets the deployer `mintArc` arbitrary ARC, `migrateUser`, and `setAddresses` until `revokeDevMode` is called. `devMode` starts `true`. Document and revoke promptly post-setup.
- `onlyManager` can call `calculateOrders` for any `callerId` with any subset of `orderIds`; selectively omitting orders reduces a user's commission. Managers are trusted but this is a powerful capability worth documenting/monitoring.
- `changeFeeReceiverAddress` and `transferOwnership` are one-shot (flag-gated); a mistaken first value is permanent. Confirm this is intended.

### I-3. `Amount.sv` (sales volume) is recorded on orders but never used in commission/ARC math, and payment validation only checks `totalAmount >= totalBv` (SV is unconstrained). Confirm SV is purely informational; otherwise add validation.

### I-4. `calculateOrders` relies on `orderId` ordering implying `createdAt` ordering for its day/week boundary logic. This holds because orders are created sequentially with `block.timestamp`, but it is an implicit invariant worth a comment.

---

## Suggested fix priority
1. **C-1** (underflow blocking ARC) and **H-1** (reentrancy/CEI) — correctness + funds.
2. **H-2** (FV full-struct overwrite) — trust boundary.
3. **M-1** (`uint8` loop), **M-2** (migration `positionTaken`), **M-3** (per-week ARC globals).
4. **M-4/M-5/M-6**, then Low/Info hardening.
