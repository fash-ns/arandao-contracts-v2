# DNMCore (`contracts/core/Core.sol`) — Contract Analysis

**Scope:** `DNMCore` and all contracts/libraries it imports or inherits (directly or via inheritance).  
**Solidity:** `^0.8.28` (checked arithmetic; no classic underflow on `uint` math).  
**Generated:** 2026-06-02

---

## 1. Architecture overview

`DNMCore` is the main on-chain MLM engine: a **4-wide binary tree** of users, **order ledger**, **pair-matching commission** (daily, then weekly after activation), **payment-token** flows, **ARC** weekly rewards, and integration with **FastValue** (20% of BV).

### Inheritance (linearized)

```
DNMCore
├── ReentrancyGuard (OpenZeppelin)
├── Users
├── Sellers
├── Orders
├── Finance
├── CalculationLogic
└── SecurityGuard (Ownable)
```

### External dependencies (interfaces only in core folder)

| Contract | Role |
|----------|------|
| `IFastValue` | Monthly FV pool, user registration, authority checks |
| `IARC` | Mintable ARC ERC20 |
| `ITwapOracle` | Price for ARC mint formula |
| `IYieldPool` | Receives payment-token “DEX” share after weekly ARC mint |
| OpenZeppelin `SafeERC20`, `ReentrancyGuard`, `Ownable` | Token safety, reentrancy, ownership |

---

## 2. Data model (libraries)

### `UserLib.User`

Tree member: parent, position (0–3), encoded `path`, BV accumulators (`childrenBv`, `childrenAggregateBv`, `normalNodesBv`), commission/ARC/FV state, migration flags.

### `OrderLib.Order`

Purchase record: buyer/seller IDs, SV/BV, `createdAt`, `existed`.

### `SellerLib.Seller`

Seller registry: total BV, last ARC week claimed, `active`.

---

## 3. Method reference by module

### 3.1 `DNMCore` (`Core.sol`)

| Function | Access | Purpose |
|----------|--------|---------|
| `constructor` | — | Sets payment token + ARC via `Finance`, owner/deployer via `SecurityGuard`, `feeReceiver`. |
| `changeFeeReceiverAddress` | `onlyOwner` | One-time update of fee skim recipient (`feeReceiverFlag`). |
| `setAddresses` | `onlyDevMode` | Sets TWAP oracle, yield pool, FastValue (`fvAddress`). |
| `migrateUser` | `onlyDevMode` | Bulk-writes `users` / `addressToUserId` from calldata (legacy bridge). |
| `mintArc` | `onlyDevMode` | Dev mint ARC via `_mintArc`. |
| `revokeDevMode` | `onlyDevMode` | Permanently disables dev-only functions. |
| `createOrder` | Whitelisted caller | Entry for Market/OrderBook: pulls payment token, fees, registers buyer/sellers, creates orders, updates BV, sends 20% BV to FV. |
| `_createOrderFromCore` | internal | Payment + validation + user creation + order loop + FV hooks. |
| `_createOrderLoop` | internal | Per-line-item seller + order + seller weekly BV. |
| `calculateOrders` | `onlyManager` | Processes given order IDs for a user: rolls BV into tree legs, runs daily/weekly commission at period boundaries, updates `lastCalculatedOrder`. |
| `_calculateCommissionForPeriod` | internal | Core “binary” matching: 3 BV pairs, step loop, flush at max steps, FV authority check, credits `withdrawableCommission`. |
| `calculateDailyCommission` | internal | Uses day index as period key. |
| `calculateWeeklyCommission` | internal | Uses `week * 7` as period key. |
| `withdrawCommission` | user + `nonReentrant` | Burns accounting balance; transfers payment token if contract balance allows. |
| `mintWeeklyARC` | **public** | Aggregates prior week steps; may reduce max steps; mints ARC and may send remainder payment token to yield pool. |
| `calculateNetworkerWeeklyARC` | user + `nonReentrant` | 50% of `lastWeekArcMintAmount` pro-rata by user’s weekly steps (requires prior-week order calc on week’s first day). |
| `calculateUserWeeklyARC` | user + `nonReentrant` | 40% pro-rata by user’s weekly BV share. |
| `calculateSellerWeeklyARC` | seller + `nonReentrant` | 10% pro-rata by seller weekly BV. |
| `getCurrentMonthNo` | view | Calendar month index from `HelpersLib`. |
| `addManager` / `revokeManager` | owner (+ deployer in dev) | Manager ACL for `calculateOrders`. |
| `addWhiteListContract` | owner (+ deployer in dev) | Allows contract to call `createOrder`. |
| `requestChangeAddress` / `cancelChangeAddressRequest` / `approveChangeAddress` | user / parent | Wallet migration with parent (or root child) approval. |

**`Amount` struct:** `sellerAddress`, `sv`, `bv` per line item in `createOrder`.

---

### 3.2 `Users` (`Users.sol`)

| Function | Purpose |
|----------|---------|
| `_getPathLength` / `_getPathByte` / `_appendToPath` | Compact tree path encoding (positions stored as `pos + 1` in bytes). |
| `_getOrCreateUser` | Register user under parent with position rules, BV gates for parent, `positionTaken`, copy path. New users get `lastCalculatedOrder = lastOrderId - 1`. |
| `_requestChangeAddress` / `_cancelChangeAddressRequest` / `_approveChangeAddress` | Address change workflow. |
| `_isSubTree` | Whether `candidateId` is under `rootId`; returns direct-child leg index (0–3). |
| `_addUserBv` | Increments user total + weekly BV. |
| `_getUserPairByIndex` / `_setUserPairByIndex` | Read/write the three commission pairs. |
| `_getUserById` / `getUserById` / `getUserIdByAddress` / `_userExistsByAddress` / `_getUserByAddress` | User lookups. |
| `_getUserDailySteps` / `_setUserDailySteps` / `_getUserWeeklyBv` | Step and weekly BV storage. |

---

### 3.3 `Sellers` (`Sellers.sol`)

| Function | Purpose |
|----------|---------|
| `_getOrCreateSeller` | Auto-register seller by address. |
| `_addSellerBv` | Seller total + `sellerWeeklyBv`. |
| `_getSellerById` / `getSellerById` / `getSellerIdByAddress` | Seller lookups. |

---

### 3.4 `Orders` (`Orders.sol`)

| Function | Purpose |
|----------|---------|
| `_createOrder` | Increment `lastOrderId`, store order with `block.timestamp`. |
| `_getOrderById` / `getOrderById` | Order lookup (`onlyExistedOrder`). |

---

### 3.5 `Finance` (`Finance.sol`)

| Function | Purpose |
|----------|---------|
| `calculateArcMintAmount` | View: ARC mint size from prior-week BV, TWAP price, supply adjustment. |
| `_mintWeeklyArc` | Mint ARC if needed; push `pastWeekBv - totalCommissionEarned` payment tokens to yield pool (capped by balance). |
| `_mintArc` | `IARC.mint`. |
| `_transferArc` / `_transferPaymentToken` / `_transferPaymentTokenFrom` | `SafeERC20` transfers. |
| `_approvePaymentToken` | `IERC20.approve` (not `forceApprove`). |
| `_getPaymentTokenBalance` | Balance helper. |
| `_addTotalWeekBv` / `_getWeeklyBv` | Global weekly BV totals. |

**State:** `totalCommissionEarned`, `totalArcEarned`, `globalDailySteps`, `globalDailyFlushOuts`, `totalCommissionEarnedByWeek`, `totalWeeklyBv`, ARC mint tracking.

---

### 3.6 `CalculationLogic` (`CalculationLogic.sol`)

| Function | Purpose |
|----------|---------|
| `_activateWeeklyCalculation` | After 72 global daily flush-outs, sets `weeklyCalculationStartTime` to next week start. |
| `_reduceMaxSteps` | Decrements `_maxSteps` when weekly commissions exceed BV budget (if weekly mode on). |
| `_isWeeklyCalculationActive` | Weekly mode flag. |
| `_getMaxSteps` / `_getBvBalance` / `_getMinBv` / `_getCommissionPerStep` | **Mutate** thresholds on first use in weekly mode (6→50 steps, 500→1000 BV balance, etc.). |

---

### 3.7 `SecurityGuard` (`SecurityGuard.sol`)

| Function | Purpose |
|----------|---------|
| `transferOwnership` | **Once** only; moves manager flag from old to new owner. |
| `_addManager` / `_revokeManager` | Off-chain operator ACL. |
| `_addWhiteListedContract` | `createOrder` callers. |
| `isOrderCreatorContract` / `isManager` | Views. |

Modifiers: `onlyOwnerAndDeployerInDevMode`, `onlyOrderCreatorContracts`, `onlyManager`, `onlyDevMode`.

---

### 3.8 `HelpersLib` (`HelpersLib.sol`)

| Function | Purpose |
|----------|---------|
| `getDayOfTs` / `getWeekOfTs` / `getStartWeekTs` | Time buckets from fixed `offset` (Mon 10 Nov 2025 UTC). |
| `getMonth` | Month index from `BokkyPooBahsDateTimeLibrary`. |
| `_isFirstDayOfWeek` | First calendar day of protocol week. |
| `getDistanceInDays` | Day difference helper. |

---

### 3.9 Libraries (`CoreLib`, `OrderLib`, `SellerLib`, `UserLib`, `SecurityGuardLib`)

Events and custom errors only (no runtime logic), except struct definitions in `UserLib` / `OrderLib` / `SellerLib`.

---

### 3.10 `IFastValue` (implemented in `contracts/fastValue/FastValue.sol`)

Called from `_createOrderFromCore` and `_calculateCommissionForPeriod`:

| Function | Purpose |
|----------|---------|
| `addMonthlyFv` | `transferFrom` Core → FV; adds to `monthlyFv[month]`. |
| `registerUserFvFromPurchase` | Extends FV enrollment months if BV milestones met. |
| `checkUserAuthorityForFvEntrance` | On super-node steps, may grant full/half FV share by registration age + BV. |

---

## 4. Main business flows

### Order creation (`createOrder`)

1. Whitelisted contract calls with buyer, parent, position, `Amount[]`, `totalAmount`.
2. Sum BV; require `totalAmount >= totalBv`.
3. `safeTransferFrom` caller → Core for `totalAmount`.
4. Skim `totalAmount - totalBv` to `feeReceiver`.
5. New buyers must meet `_getMinBv()` (100 USDT-scale units, or 300 in weekly mode).
6. `_getOrCreateUser` + per-amount orders + weekly BV totals.
7. Approve FV for `20% * totalBv`; `addMonthlyFv` + `registerUserFvFromPurchase`.

### Commission (`calculateOrders` → `_calculateCommissionForPeriod`)

1. Manager passes `callerId` and `orderIds[]`.
2. For each order: time guards (prior day/week only); may trigger interim daily/weekly commission when period changes.
3. If buyer in caller’s subtree (not self): add `order.bv` to `childrenBv`, `childrenAggregateBv`, and `normalNodesBv[childPosition/2]`.
4. Match pairs while both sides ≥ `_bvBalance` and steps &lt; `_maxSteps`; pay `_commissionPerStep` per step.
5. At max steps: zero pair BV, increment global flush counter (72 → weekly mode).
6. Credit `withdrawableCommission`; update global commission trackers.

### ARC weekly distribution

1. `mintWeeklyARC` (callable by anyone): compute prior week steps, optionally `_reduceMaxSteps`, `_mintWeeklyArc`.
2. Users/sellers claim via three `calculate*WeeklyArc` functions (50% / 40% / 10% splits).

---

## 5. Known issues and risks

Severity labels: **Critical** / **High** / **Medium** / **Low** / **Informational**.

### 5.1 Accounting and token handling

| Issue | Severity | Details |
|-------|----------|---------|
| **`totalArcEarned` never incremented** | **High** | `totalArcEarned` is initialized to 0 and only used in `calculateArcMintAmount` / `_mintWeeklyArc` as `balanceOf(core) - totalArcEarned` (“excess ARC”). `_transferArc` does **not** increase `totalArcEarned`. After networker/user/seller ARC claims, excess balance is **overestimated**, so the contract may **over-mint** ARC on the next `mintWeeklyARC`. |
| **`totalCommissionEarned` vs withdrawals** | **Low** | Withdrawals reduce `totalCommissionEarned`; design is coherent if it represents outstanding liability. `dexTransferAmount = pastWeekBv - totalCommissionEarned` can still desync if commissions are earned but never withdrawn and logic assumptions change. |
| **Raw `approve` instead of `SafeERC20.forceApprove`** | **Medium** | `_approvePaymentToken` and `_mintWeeklyArc` use `IERC20.approve`. Tokens like USDT often require resetting allowance to 0 first; also leftover allowance is a classic ERC20 footgun. Transfers use `SafeERC20`; approvals do not. |
| **Fee-on-transfer / rebasing payment tokens** | **High** (if such token used) | `createOrder` assumes `totalAmount` received equals requested amount. Deflationary tokens break BV vs balance invariants and FV `transferFrom`. |
| **No balance check before ARC payout** | **Medium** | `calculate*WeeklyArc` calls `_transferArc` without verifying Core’s ARC balance ≥ share; fails at transfer or drains unrelated ARC held by Core. |

Solidity **0.8+** reverts on underflow/overflow; classic uint underflow is not applicable unless `unchecked` is used (it is not in these files).

---

### 5.2 `calculateOrders` and manager trust

| Issue | Severity | Details |
|-------|----------|---------|
| **Duplicate `orderIds` in one call** | **High** | Loop checks `orderIds[i] > user.lastCalculatedOrder` against the **initial** `lastCalculatedOrder`, not running max. Same ID twice **double-counts BV** and steps. |
| **`lastCalculatedOrder` = last array element, not max ID** | **High** | Passing `[5, 3]` processes both but sets `lastCalculatedOrder = 3`, so order `4` can be skipped permanently for that user. |
| **Non-contiguous / out-of-order IDs** | **Medium** | No requirement that IDs are sorted or sequential; period-boundary commission uses order timestamps in array order, which can mis-trigger daily/weekly settlements. |
| **Centralized manager** | **Informational** | `onlyManager` can grief or mis-allocate; by design but not trustless. |

---

### 5.3 Loops and type limits

| Issue | Severity | Details |
|-------|----------|---------|
| **`uint8` loop index in `calculateOrders`** | **Medium** | `for (uint8 i = 0; i < orderIdsLen; i++)` with `orderIdsLen` up to `uint16`: if `orderIds.length > 255`, only the first **255** entries run. |
| **`uint16` cast of `orderIds.length`** | **Low** | Length &gt; 65535 truncates silently. Unlikely on-chain but incorrect. |

---

### 5.4 Reentrancy and external calls

| Issue | Severity | Details |
|-------|----------|---------|
| **`createOrder` without `nonReentrant`** | **Medium** | External calls to `IFastValue` after state updates but mid-flow; malicious FV could reenter if it were whitelisted as order creator (unlikely) or exploit composability. Payment pulls happen before FV calls. |
| **`mintWeeklyARC` public, no reentrancy guard** | **Low** | Calls `mint`, `approve`, `notifyReward` on external contracts; state updated before externals in `_mintWeeklyArc` mostly after mint logic. |
| **Protected paths** | **Informational** | `withdrawCommission` and ARC claim functions use `nonReentrant`. |

---

### 5.5 Configuration and ops

| Issue | Severity | Details |
|-------|----------|---------|
| **`fvAddress` / oracle / yield pool unset** | **High** | `createOrder` and `_mintWeeklyArc` call external addresses set only in `setAddresses` (dev). Zero address → failed txs or lost funds. Must be set before production use and dev revoked. |
| **One-time `feeReceiver` / ownership** | **Informational** | Cannot rotate fee receiver or owner after first change; recovery requires new deployment or upgrade. |
| **`migrateUser` unchecked** | **High** (dev abuse) | No tree validation; `onlyDevMode` can overwrite graph state incorrectly. |
| **`devMode` deployer-only** | **Informational** | Deployer retains powerful hooks until `revokeDevMode`. |

---

### 5.6 Logic and product rules

| Issue | Severity | Details |
|-------|----------|---------|
| **`childrenAggregateBv` written, never read** | **Low** | Extra storage gas; possible incomplete feature or dead field. |
| **`_getMaxSteps` / `_getBvBalance` / … mutate on read** | **Medium** | First commission calc in weekly mode permanently bumps global parameters (6→50 steps, etc.) inside getters — surprising side effects and ordering dependencies. |
| **`superNodeTotalSteps > 1` for FV** | **Informational** | Requires more than one lifetime super-node step, not per period. |
| **ARC: first day of week blocked** | **Informational** | `mintWeeklyARC` / networker ARC require not first protocol week day; networker also needs `eligibleArcWithdrawWeekNo` set via `calculateOrders` on week boundary. |
| **Three ARC claim functions share one `lastWeekArcMintAmount`** | **Low** | Race: multiple users calling mint in same block is guarded by `arcMintWeekNumber`; shares can still exceed minted ARC if accounting wrong (see `totalArcEarned`). |
| **Commission withdraw requires float** | **Informational** | `withdrawCommission` needs Core payment-token balance ≥ amount (commissions funded by later purchases / yield routing). |

---

### 5.7 Path / tree encoding

| Issue | Severity | Details |
|-------|----------|---------|
| **Path byte 0 means “unset” in length** | **Low** | `_getPathLength` stops at first zero byte; encoding must never write zero for valid positions (uses `pos+1`, OK for 0–3). |
| **`_isSubTree` inactive users** | **Informational** | Returns `(false, 0)` if either user inactive. |

---

### 5.8 ERC20 / OpenZeppelin notes

| Topic | Assessment |
|-------|------------|
| **Transfer return value** | Mitigated via `SafeERC20` for transfers. |
| **Approve race (ERC20)** | Still relevant for approvals to FV and yield pool; use `forceApprove` or zero-then-set. |
| **`transfer` vs `transferFrom`** | Inbound uses `safeTransferFrom` from whitelisted caller (must approve Core). |

---

### 5.9 FastValue integration (imported interface)

| Issue | Severity | Details |
|-------|----------|---------|
| **20% BV approval exact amount** | **Low** | Repeated purchases reset approve to new amount; USDT compatibility as above. |
| **FV returns updated `User` in memory** | **Informational** | `checkUserAuthorityForFvEntrance` assignment `users[userId] = fv.check...` relies on FV being correct and `onlyCoreContract` on FV. |

---

## 6. Security controls (positive)

- Whitelist for order creation; managers for commission processing.
- `ReentrancyGuard` on user withdrawals and ARC claims.
- `SafeERC20` on token transfers.
- Checked arithmetic (Solidity 0.8).
- Position uniqueness and parent BV rules for placements.
- Time gates: no same-day / same-week order processing for commissions.
- Ownable + one-time ownership transfer; dev mode gated to deployer.

---

## 7. Suggested review priorities

1. Fix or wire **`totalArcEarned`** (increment on every ARC outbound transfer).  
2. Harden **`calculateOrders`**: dedupe IDs, set `lastCalculatedOrder = max(orderIds)`, optional sort by `createdAt`.  
3. Replace **`uint8`** loop counter or cap array length explicitly.  
4. Use **`SafeERC20.forceApprove`** (or approve 0 then amount) for USDT-like tokens.  
5. Add **`nonReentrant`** on `createOrder` / `_createOrderFromCore` if FV is not fully trusted.  
6. Document operational requirement: **`setAddresses`** before traffic; **`revokeDevMode`** before mainnet.

---

## 8. File index (core package)

| File | Role |
|------|------|
| `Core.sol` | `DNMCore` main contract |
| `Users.sol`, `Sellers.sol`, `Orders.sol` | State and CRUD |
| `Finance.sol`, `CalculationLogic.sol` | Money and parameters |
| `SecurityGuard.sol` | ACL |
| `UserLib.sol`, `OrderLib.sol`, `SellerLib.sol`, `CoreLib.sol`, `HelpersLib.sol`, `SecurityGuardLib.sol` | Types, events, time math |
| `IFastValue.sol`, `IARC.sol`, `ITwapOracle.sol`, `IYieldPool.sol` | External interfaces |
| `BokkyPooBahsDateTimeLibrary.sol` | Date helpers |

Related but outside `contracts/core/`: `contracts/fastValue/FastValue.sol`, `contracts/market/Market.sol`, `contracts/orderBook/OrderBook.sol` (call `createOrder` on Core).
