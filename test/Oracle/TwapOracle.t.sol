// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {Test} from "forge-std/Test.sol";
import {TwapOracle} from "../../src/Oracle/TwapOracle.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

// ─── Mock tokens ──────────────────────────────────────────────────────────────

contract MockToken is ERC20 {
    uint8 private _decimals;

    constructor(string memory name, string memory symbol, uint8 d) ERC20(name, symbol) {
        _decimals = d;
    }

    function decimals() public view override returns (uint8) {
        return _decimals;
    }

    function mint(address to, uint256 amount) external {
        _mint(to, amount);
    }
}

// ─── Mock Uniswap V2 pair ─────────────────────────────────────────────────────
//
// Faithfully simulates Uniswap V2's cumulative price accumulators:
//   • price0CumulativeLast accumulates (reserve1/reserve0 * 2^112) per second
//   • price1CumulativeLast accumulates (reserve0/reserve1 * 2^112) per second
//
// setReserves() is the only admin function; it updates the pair state exactly as
// UniswapV2Pair._update() does, so the cumulative prices track real elapsed time.

contract MockUniswapV2Pair {
    address public token0;
    address public token1;

    uint112 private _reserve0;
    uint112 private _reserve1;
    uint32  private _blockTimestampLast;

    uint256 public price0CumulativeLast;
    uint256 public price1CumulativeLast;

    constructor(address _token0, address _token1, uint112 r0, uint112 r1) {
        token0 = _token0;
        token1 = _token1;
        // Initialise without updating cumulatives (matches a freshly-minted V2 pair).
        _reserve0 = r0;
        _reserve1 = r1;
        _blockTimestampLast = uint32(block.timestamp % 2 ** 32);
    }

    function getReserves() external view returns (uint112, uint112, uint32) {
        return (_reserve0, _reserve1, _blockTimestampLast);
    }

    /**
     * @dev Simulates a swap / liquidity event that updates reserves.
     *      Advances cumulative prices for the time elapsed since the last call,
     *      mirroring UniswapV2Pair._update().
     */
    function setReserves(uint112 r0, uint112 r1) external {
        uint32 blockTimestamp = uint32(block.timestamp % 2 ** 32);
        unchecked {
            uint32 timeElapsed = blockTimestamp - _blockTimestampLast;
            if (timeElapsed > 0 && _reserve0 != 0 && _reserve1 != 0) {
                price0CumulativeLast += (uint256(_reserve1) << 112) / uint256(_reserve0) * uint256(timeElapsed);
                price1CumulativeLast += (uint256(_reserve0) << 112) / uint256(_reserve1) * uint256(timeElapsed);
            }
        }
        _reserve0 = r0;
        _reserve1 = r1;
        _blockTimestampLast = blockTimestamp;
    }
}

// ─── Base harness ─────────────────────────────────────────────────────────────

contract TwapOracleTest is Test {
    uint256 internal constant ARC_UNIT  = 1e18;
    uint256 internal constant USDT_UNIT = 1e6;
    uint256 internal constant PERIOD    = 8 hours;

    MockToken           internal arc;
    MockToken           internal usdt;
    MockUniswapV2Pair   internal pair;
    TwapOracle          internal oracle;

    address internal lpActivator = makeAddr("lpActivator");
    address internal keeper      = makeAddr("keeper");
    address internal anyone      = makeAddr("anyone");

    // Pool starts at 300 USDT per ARC (reserve: 1 000 ARC : 300 000 USDT)
    uint112 internal constant R_ARC  = 1_000 * 1e18;
    uint112 internal constant R_USDT = 300_000 * 1e6;

    uint256 internal constant FIXED_PRICE = 300 * USDT_UNIT;

    function setUp() public virtual {
        arc  = new MockToken("ARC", "ARC", 18);
        usdt = new MockToken("USDT", "USDT", 6);

        // token0 = ARC, token1 = USDT (price0 = USDT/ARC = quote/token)
        pair = new MockUniswapV2Pair(address(arc), address(usdt), R_ARC, R_USDT);

        oracle = new TwapOracle(address(arc), address(usdt), lpActivator, FIXED_PRICE);
    }

    // ─── Helpers ──────────────────────────────────────────────────────────────

    function _activate() internal {
        vm.prank(lpActivator);
        oracle.activateTwap(address(pair), keeper);
    }

    function _warpAndUpdate() internal {
        vm.warp(block.timestamp + PERIOD);
        // Advance the pair's cumulative prices (simulate a swap touching the pair).
        pair.setReserves(R_ARC, R_USDT);
        vm.prank(keeper);
        oracle.update();
    }
}

// ══════════════════════════════════════════════════════════════════════════════
// §1  Constructor
// ══════════════════════════════════════════════════════════════════════════════

contract Test_Constructor is TwapOracleTest {
    function test_Immutables() public view {
        assertEq(oracle.token(), address(arc));
        assertEq(oracle.quoteToken(), address(usdt));
        assertEq(oracle.lpActivator(), lpActivator);
        assertEq(oracle.FIXED_PRICE(), FIXED_PRICE);
        assertEq(oracle.tokenDecimals(), 18);
    }

    function test_ZeroAddress_Token_Reverts() public {
        vm.expectRevert(TwapOracle.ZeroAddress.selector);
        new TwapOracle(address(0), address(usdt), lpActivator, FIXED_PRICE);
    }

    function test_ZeroAddress_QuoteToken_Reverts() public {
        vm.expectRevert(TwapOracle.ZeroAddress.selector);
        new TwapOracle(address(arc), address(0), lpActivator, FIXED_PRICE);
    }

    function test_ZeroAddress_LpActivator_Reverts() public {
        vm.expectRevert(TwapOracle.ZeroAddress.selector);
        new TwapOracle(address(arc), address(usdt), address(0), FIXED_PRICE);
    }
}

// ══════════════════════════════════════════════════════════════════════════════
// §2  Phase-1 fixed price
// ══════════════════════════════════════════════════════════════════════════════

contract Test_Phase1 is TwapOracleTest {
    function test_GetPrice_ReturnsFixedPrice_BeforeActivation() public view {
        assertEq(oracle.getPrice(), FIXED_PRICE);
    }

    function test_GetPrice_ReturnsFixedPrice_AfterActivationButBeforeFirstUpdate() public {
        _activate();
        assertEq(oracle.getPrice(), FIXED_PRICE);
    }

    function test_TwapActive_FalseBeforeActivation() public view {
        assertFalse(oracle.twapActive());
    }

    function test_HasBeenUpdated_FalseBeforeFirstUpdate() public {
        _activate();
        assertFalse(oracle.hasBeenUpdated());
    }

    function test_UpdateReady_FalseBeforeActivation() public view {
        assertFalse(oracle.updateReady());
    }

    function test_NextUpdateIn_MaxBeforeActivation() public view {
        assertEq(oracle.nextUpdateIn(), type(uint256).max);
    }
}

// ══════════════════════════════════════════════════════════════════════════════
// §3  activateTwap — access control & validation
// ══════════════════════════════════════════════════════════════════════════════

contract Test_ActivateTwap is TwapOracleTest {
    function test_OnlyLpActivator_CanActivate() public {
        vm.prank(anyone);
        vm.expectRevert(TwapOracle.NotLpActivator.selector);
        oracle.activateTwap(address(pair), keeper);
    }

    function test_CannotActivateTwice() public {
        _activate();
        vm.prank(lpActivator);
        vm.expectRevert(TwapOracle.TwapAlreadyActive.selector);
        oracle.activateTwap(address(pair), keeper);
    }

    function test_ZeroPairAddress_Reverts() public {
        vm.prank(lpActivator);
        vm.expectRevert(TwapOracle.ZeroAddress.selector);
        oracle.activateTwap(address(0), keeper);
    }

    function test_ZeroKeeperAddress_Reverts() public {
        vm.prank(lpActivator);
        vm.expectRevert(TwapOracle.ZeroAddress.selector);
        oracle.activateTwap(address(pair), address(0));
    }

    function test_InvalidPair_NoToken_Reverts() public {
        // Pair that does not contain `token` (ARC).
        MockUniswapV2Pair wrongPair = new MockUniswapV2Pair(
            address(usdt), makeAddr("other"), uint112(1000 * USDT_UNIT), uint112(1000 * USDT_UNIT)
        );
        vm.prank(lpActivator);
        vm.expectRevert(TwapOracle.InvalidPair.selector);
        oracle.activateTwap(address(wrongPair), keeper);
    }

    function test_InvalidPair_MissingQuoteToken_Reverts() public {
        // Pair contains ARC but not USDT.
        MockToken other = new MockToken("OTHER", "OTHER", 18);
        MockUniswapV2Pair wrongPair = new MockUniswapV2Pair(
            address(arc), address(other), uint112(1000 * ARC_UNIT), uint112(1000 * ARC_UNIT)
        );
        vm.prank(lpActivator);
        vm.expectRevert(TwapOracle.InvalidPair.selector);
        oracle.activateTwap(address(wrongPair), keeper);
    }

    function test_StateAfterActivation() public {
        vm.expectEmit(true, true, false, false);
        emit TwapOracle.TwapActivated(address(pair), keeper);
        _activate();

        assertTrue(oracle.twapActive());
        assertEq(oracle.keeper(), keeper);
        assertEq(address(oracle.pair()), address(pair));
    }

    // Pair where token is token1 (USDT=token0, ARC=token1) should also work.
    function test_Activate_TokenAsToken1() public {
        MockUniswapV2Pair flippedPair = new MockUniswapV2Pair(
            address(usdt), address(arc), R_USDT, R_ARC
        );
        vm.prank(lpActivator);
        oracle.activateTwap(address(flippedPair), keeper);
        assertTrue(oracle.twapActive());
    }
}

// ══════════════════════════════════════════════════════════════════════════════
// §4  update() — gating and mechanics
// ══════════════════════════════════════════════════════════════════════════════

contract Test_Update is TwapOracleTest {
    function setUp() public override {
        super.setUp();
        _activate();
    }

    function test_OnlyKeeper_CanUpdate() public {
        vm.warp(block.timestamp + PERIOD);
        pair.setReserves(R_ARC, R_USDT);

        vm.prank(anyone);
        vm.expectRevert(TwapOracle.NotKeeper.selector);
        oracle.update();
    }

    function test_Reverts_BeforePeriodElapsed() public {
        vm.warp(block.timestamp + PERIOD - 1);
        pair.setReserves(R_ARC, R_USDT);

        vm.prank(keeper);
        vm.expectRevert(abi.encodeWithSelector(TwapOracle.PeriodNotElapsed.selector, PERIOD - 1, PERIOD));
        oracle.update();
    }

    function test_Reverts_IfTwapNotActive() public {
        // Deploy a fresh oracle without activating it; any caller hits TwapNotActive first.
        TwapOracle fresh = new TwapOracle(address(arc), address(usdt), lpActivator, FIXED_PRICE);
        vm.expectRevert(TwapOracle.TwapNotActive.selector);
        fresh.update(); // keeper check is skipped — TwapNotActive fires first
    }

    function test_ExactlyPeriodElapsed_Succeeds() public {
        vm.warp(block.timestamp + PERIOD);
        pair.setReserves(R_ARC, R_USDT);

        vm.prank(keeper);
        oracle.update(); // must not revert
        assertTrue(oracle.hasBeenUpdated());
    }

    function test_HasBeenUpdated_TrueAfterFirstUpdate() public {
        _warpAndUpdate();
        assertTrue(oracle.hasBeenUpdated());
    }

    function test_PriceAverageX112_NonzeroAfterUpdate() public {
        _warpAndUpdate();
        assertGt(oracle.priceAverageX112(), 0);
    }

    function test_EmitsPriceUpdatedEvent() public {
        vm.warp(block.timestamp + PERIOD);
        pair.setReserves(R_ARC, R_USDT);

        vm.expectEmit(false, false, false, false); // only check it fires
        emit TwapOracle.PriceUpdated(0, 0);
        vm.prank(keeper);
        oracle.update();
    }

    function test_CanUpdateAgainAfterNextPeriod() public {
        _warpAndUpdate();
        vm.warp(block.timestamp + PERIOD);
        pair.setReserves(R_ARC, R_USDT);

        vm.prank(keeper);
        oracle.update(); // second update — must not revert
    }

    function test_CannotUpdateTwiceInSamePeriod() public {
        _warpAndUpdate();
        // Only 1 second has passed since last update.
        vm.warp(block.timestamp + 1);
        pair.setReserves(R_ARC, R_USDT);

        vm.prank(keeper);
        vm.expectRevert(
            abi.encodeWithSelector(TwapOracle.PeriodNotElapsed.selector, 1, PERIOD)
        );
        oracle.update();
    }
}

// ══════════════════════════════════════════════════════════════════════════════
// §5  getPrice() — TWAP correctness
// ══════════════════════════════════════════════════════════════════════════════

contract Test_GetPrice is TwapOracleTest {
    function setUp() public override {
        super.setUp();
        _activate();
    }

    // 5.1 — Stable pool at 300 USDT/ARC: getPrice() should return 300e6.
    function test_GetPrice_StablePool_Returns300Usdt() public {
        _warpAndUpdate();
        uint256 price = oracle.getPrice();
        // Allow 1 unit of rounding due to integer division in UQ112x112.
        assertApproxEqAbs(price, 300 * USDT_UNIT, 1, "TWAP price should be ~300 USDT");
    }

    // 5.2 — Price averages 225 USDT when reserves are 300 for the first half-PERIOD
    //         and 150 for the second half-PERIOD within a single update window.
    function test_GetPrice_HalfPeriodAt300_HalfAt150_Averages225() public {
        // Activation snapshot was taken in setUp(); pair is at 300 USDT/ARC.

        // ── First half-PERIOD at 300 USDT/ARC ───────────────────────────────
        vm.warp(block.timestamp + PERIOD / 2);
        pair.setReserves(R_ARC, R_USDT); // advance cumulatives for PERIOD/2 at 300, keep same reserves

        // ── Switch to 150 USDT/ARC (same block → no cumulative advance) ─────
        pair.setReserves(R_ARC, R_USDT / 2);

        // ── Second half-PERIOD at 150 USDT/ARC ──────────────────────────────
        vm.warp(block.timestamp + PERIOD / 2);
        pair.setReserves(R_ARC, R_USDT / 2); // advance cumulatives for PERIOD/2 at 150

        vm.prank(keeper);
        oracle.update();

        uint256 price = oracle.getPrice();
        // TWAP = (PERIOD/2 × 300 + PERIOD/2 × 150) / PERIOD = 225 USDT
        assertApproxEqAbs(price, 225 * USDT_UNIT, 2, "TWAP should average 225 USDT");
    }

    // 5.3 — After activation but before first update: still returns FIXED_PRICE.
    function test_GetPrice_BeforeFirstUpdate_ReturnsFixed() public view {
        assertEq(oracle.getPrice(), FIXED_PRICE);
    }

    // 5.4 — Works correctly when token is token1 in the pair.
    function test_GetPrice_TokenAsToken1() public {
        // Use a dedicated oracle so we don't conflict with the setUp activation.
        TwapOracle flippedOracle = new TwapOracle(address(arc), address(usdt), lpActivator, FIXED_PRICE);

        // Flipped pair: USDT=token0, ARC=token1 → price1 tracks USDT/ARC.
        MockUniswapV2Pair flippedPair = new MockUniswapV2Pair(
            address(usdt), address(arc), R_USDT, R_ARC
        );

        vm.prank(lpActivator);
        flippedOracle.activateTwap(address(flippedPair), keeper);

        vm.warp(block.timestamp + PERIOD);
        flippedPair.setReserves(R_USDT, R_ARC);
        vm.prank(keeper);
        flippedOracle.update();

        uint256 price = flippedOracle.getPrice();
        assertApproxEqAbs(price, 300 * USDT_UNIT, 1, "flipped-pair price should be ~300 USDT");
    }

    // 5.5 — Multiple sequential updates accumulate correctly.
    function test_GetPrice_MultipleUpdates_ConvergesCorrectly() public {
        // Run three full PERIOD windows at 300 USDT/ARC.
        for (uint256 i; i < 3; ++i) {
            vm.warp(block.timestamp + PERIOD);
            pair.setReserves(R_ARC, R_USDT);
            vm.prank(keeper);
            oracle.update();
        }
        // Each window is still 300 USDT/ARC, so TWAP = 300.
        assertApproxEqAbs(oracle.getPrice(), 300 * USDT_UNIT, 1, "price should remain stable");
    }

    // 5.6 — Fuzz: single stable price window always returns approximately that price.
    function testFuzz_GetPrice_StablePool(uint112 r0, uint112 r1) public {
        // Reasonable reserve range: 1 token to 1_000_000 tokens (in base units).
        r0 = uint112(bound(uint256(r0), 1 * ARC_UNIT, 1_000_000 * ARC_UNIT));
        r1 = uint112(bound(uint256(r1), 1 * USDT_UNIT, 1_000_000_000 * USDT_UNIT));

        // Use a dedicated oracle so we don't conflict with the setUp activation.
        TwapOracle fuzzOracle = new TwapOracle(address(arc), address(usdt), lpActivator, FIXED_PRICE);
        MockUniswapV2Pair fuzzPair = new MockUniswapV2Pair(address(arc), address(usdt), r0, r1);

        vm.prank(lpActivator);
        fuzzOracle.activateTwap(address(fuzzPair), keeper);

        vm.warp(block.timestamp + PERIOD);
        fuzzPair.setReserves(r0, r1);
        vm.prank(keeper);
        fuzzOracle.update();

        uint256 price = fuzzOracle.getPrice();

        // Expected: (r1/r0) * 1e18 in 6-decimal USDT = r1 * 1e18 / r0
        uint256 expected = uint256(r1) * ARC_UNIT / uint256(r0);
        // Allow 1 USDT-base-unit of rounding from UQ112x112 integer division.
        assertApproxEqAbs(price, expected, 1, "TWAP price diverges from spot");
    }
}

// ══════════════════════════════════════════════════════════════════════════════
// §6  updateReady() and nextUpdateIn()
// ══════════════════════════════════════════════════════════════════════════════

contract Test_ViewHelpers is TwapOracleTest {
    function setUp() public override {
        super.setUp();
        _activate();
    }

    function test_UpdateReady_FalseJustAfterActivation() public view {
        assertFalse(oracle.updateReady());
    }

    function test_UpdateReady_TrueAfterPeriod() public {
        vm.warp(block.timestamp + PERIOD);
        assertTrue(oracle.updateReady());
    }

    function test_UpdateReady_FalseJustAfterUpdate() public {
        _warpAndUpdate();
        assertFalse(oracle.updateReady());
    }

    function test_NextUpdateIn_DecreasesThenZero() public {
        uint256 remaining = oracle.nextUpdateIn();
        assertEq(remaining, PERIOD); // no time elapsed since activation

        vm.warp(block.timestamp + PERIOD / 2);
        assertApproxEqAbs(oracle.nextUpdateIn(), PERIOD / 2, 1);

        vm.warp(block.timestamp + PERIOD / 2);
        assertEq(oracle.nextUpdateIn(), 0);
    }

    function test_NextUpdateIn_ZeroAfterUpdateDue() public {
        vm.warp(block.timestamp + PERIOD + 1 hours);
        assertEq(oracle.nextUpdateIn(), 0);
    }

    function test_NextUpdateIn_ResetsAfterUpdate() public {
        _warpAndUpdate();
        assertApproxEqAbs(oracle.nextUpdateIn(), PERIOD, 1);
    }
}

// ══════════════════════════════════════════════════════════════════════════════
// §7  Edge cases & invariants
// ══════════════════════════════════════════════════════════════════════════════

contract Test_EdgeCases is TwapOracleTest {
    // 7.1 — Fixed price is returned even after activation, before first update.
    function test_FixedPrice_PersistsUntilFirstUpdate() public {
        _activate();
        vm.warp(block.timestamp + PERIOD - 1);
        assertEq(oracle.getPrice(), FIXED_PRICE, "should still be fixed price before PERIOD");
    }

    // 7.2 — getPrice() never returns 0 (no zero-price window).
    function test_GetPrice_NeverZero() public {
        // Before activation.
        assertGt(oracle.getPrice(), 0);
        // After activation, before first update.
        _activate();
        assertGt(oracle.getPrice(), 0);
        // After first update.
        _warpAndUpdate();
        assertGt(oracle.getPrice(), 0);
    }

    // 7.3 — Long gap between activation and first update still produces correct TWAP.
    function test_LongGapBeforeFirstUpdate() public {
        _activate();
        // Wait 3× the PERIOD before the first update.
        vm.warp(block.timestamp + 3 * PERIOD);
        pair.setReserves(R_ARC, R_USDT);
        vm.prank(keeper);
        oracle.update();

        uint256 price = oracle.getPrice();
        assertApproxEqAbs(price, 300 * USDT_UNIT, 1, "long-gap TWAP should still be ~300 USDT");
    }

    // 7.4 — A committed TWAP snapshot is immutable; a price spike after window 1 closes
    //         does not retroactively change window 1's price, but window 2 fully reflects it.
    function test_PriceSpike_ClosedWindowUnchanged_NextWindowReflectsNewPrice() public {
        _activate();

        // Window 1: full PERIOD at 300 USDT/ARC → TWAP = 300.
        vm.warp(block.timestamp + PERIOD);
        pair.setReserves(R_ARC, R_USDT);
        vm.prank(keeper);
        oracle.update();
        assertApproxEqAbs(oracle.getPrice(), 300 * USDT_UNIT, 1, "window 1 TWAP should be 300");

        // Reserves spike to 600 USDT/ARC immediately after window 1 snapshot.
        pair.setReserves(R_ARC, R_USDT * 2);

        // Window 2: full PERIOD at 600 USDT/ARC → TWAP = 600.
        vm.warp(block.timestamp + PERIOD);
        pair.setReserves(R_ARC, R_USDT * 2);
        vm.prank(keeper);
        oracle.update();
        assertApproxEqAbs(oracle.getPrice(), 600 * USDT_UNIT, 2, "window 2 TWAP should be 600");
    }

    // 7.5 — Keeper can be updated implicitly by activating a second time (not possible: one-shot).
    function test_ActivateTwap_OnlyOnce_CannotChangeKeeper() public {
        _activate();
        vm.prank(lpActivator);
        vm.expectRevert(TwapOracle.TwapAlreadyActive.selector);
        oracle.activateTwap(address(pair), makeAddr("newKeeper"));
    }

    // 7.6 — updateReady() and nextUpdateIn() match expectations precisely.
    function test_UpdateReady_And_NextUpdateIn_Consistent() public {
        _activate();
        vm.warp(block.timestamp + PERIOD);
        assertTrue(oracle.updateReady());
        assertEq(oracle.nextUpdateIn(), 0);
    }
}
