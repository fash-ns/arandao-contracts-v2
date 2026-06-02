// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {Test, console} from "forge-std/Test.sol";
import {Dex} from "../../src/Dex/Dex.sol";
import {DexStorage} from "../../src/Dex/DexCore/DexStorage.sol";
import {DexErrors} from "../../src/Dex/DexCore/DexErrors.sol";
import {MockToken} from "../mocks/MockToken.sol";

contract DexTest is Test {
    Dex public dex;
    MockToken public arc;
    MockToken public usdt;

    address public alice = address(0xA11CE);
    address public bob = address(0xB0B);
    address public charlie = address(0xC11);
    address public feeReceiver = address(0xFEE);

    // helper to produce custom error selector bytes for expectRevert
    function errSel(string memory sig) internal pure returns (bytes memory) {
        return abi.encodeWithSelector(bytes4(keccak256(bytes(sig))));
    }

    function setUp() public {
        // Deploy mock tokens: ARC and USDT
        arc = new MockToken(address(this), 100_000_000e18);
        usdt = new MockToken(address(this), 100_000_000e6);

        // Deploy Dex directly (no owner)
        dex = new Dex(address(arc), address(usdt), feeReceiver);

        // Mint tokens to actors
        arc.mint(alice, 1_000_000e18);
        arc.mint(bob, 1_000_000e18);
        arc.mint(charlie, 1_000_000e18);

        usdt.mint(alice, 1_000_000e6);
        usdt.mint(bob, 1_000_000e6);
        usdt.mint(charlie, 1_000_000e6);

        // Preparing approvals
        vm.startPrank(alice);
        arc.approve(address(dex), type(uint256).max);
        usdt.approve(address(dex), type(uint256).max);
        vm.stopPrank();

        vm.startPrank(bob);
        arc.approve(address(dex), type(uint256).max);
        usdt.approve(address(dex), type(uint256).max);
        vm.stopPrank();

        vm.startPrank(charlie);
        arc.approve(address(dex), type(uint256).max);
        usdt.approve(address(dex), type(uint256).max);
        vm.stopPrank();
    }

    /* -------------------------------------------------------------------
       Happy-path & core behavior tests
       ------------------------------------------------------------------- */

    function testPlaceSellAndExecuteFullFill() public {
        // alice places a sell order: sell 100 ARC at price 2 USDT/ARC
        vm.prank(alice);
        dex.placeSellOrder(100e18, 2e6);

        // order id should be 1
        (,, bool isSell, uint256 amount, uint256 p,,) = dex.orders(1);
        assertTrue(isSell);
        assertEq(amount, 100e18);
        assertEq(p, 2e6);

        // bob will execute the order, fully filling amount 100
        // bob must send usdtTraded = amount * price / 1e18 = 200 USDT
        uint256 usdtTraded = (100e18 * 2e6) / 1e18; // 200e6

        // pre-check balances
        uint256 aliceUsdtBefore = usdt.balanceOf(alice);
        uint256 bobArcBefore = arc.balanceOf(bob);
        uint256 feeUsdtBefore = usdt.balanceOf(feeReceiver);
        uint256 feeArcBefore = arc.balanceOf(feeReceiver);

        vm.prank(bob);
        dex.executeOrder(1, 100e18);

        // Read the applicable fee tier for this volume (tier 0 for small trades)
        (, uint16 makerBps0, uint16 takerBps0) = dex.feeTiers(0);

        uint256 usdtFee = (usdtTraded * uint256(makerBps0)) / 10000;
        uint256 arcFee = (100e18 * uint256(takerBps0)) / 10000;

        assertEq(usdt.balanceOf(alice), aliceUsdtBefore + (usdtTraded - usdtFee));
        assertEq(arc.balanceOf(bob), bobArcBefore + (100e18 - arcFee));
        assertEq(usdt.balanceOf(feeReceiver), feeUsdtBefore + usdtFee);
        assertEq(arc.balanceOf(feeReceiver), feeArcBefore + arcFee);

        DexStorage.Order memory ord = dex.getOrder(1);
        assertEq(uint256(ord.status), uint256(DexStorage.Status.Executed));
        assertEq(ord.amount, 0);
    }

    function testPlaceBuyAndExecuteFullFill() public {
        console.log("=== Test: Full Fill Buy Order with Fee Accounting ===");

        uint256 amountArc = 200e18;
        uint256 price = 1e6;

        vm.prank(alice);
        dex.placeBuyOrder(amountArc, price);

        uint256 aliceArcBefore = arc.balanceOf(alice);
        uint256 bobUsdtBefore = usdt.balanceOf(bob);
        uint256 feeUsdtBefore = usdt.balanceOf(feeReceiver);
        uint256 feeArcBefore = arc.balanceOf(feeReceiver);

        vm.prank(bob);
        dex.executeOrder(1, amountArc);

        (, uint16 makerBps0, uint16 takerBps0) = dex.feeTiers(0);

        uint256 usdtTraded = (amountArc * price) / 1e18;
        uint256 usdtFee = (usdtTraded * makerBps0) / 10000;
        uint256 arcFee = (amountArc * takerBps0) / 10000;

        assertEq(arc.balanceOf(alice), aliceArcBefore + (amountArc - arcFee), "Alice ARC wrong");
        assertEq(usdt.balanceOf(bob), bobUsdtBefore + (usdtTraded - usdtFee), "Bob USDT wrong");
        assertEq(usdt.balanceOf(feeReceiver), feeUsdtBefore + usdtFee, "USDT Fee wrong");
        assertEq(arc.balanceOf(feeReceiver), feeArcBefore + arcFee, "ARC Fee wrong");

        DexStorage.Order memory ord = dex.getOrder(1);
        assertEq(uint256(ord.status), uint256(DexStorage.Status.Executed));
        assertEq(ord.amount, 0);
    }

    function testPartialFillBuyOrder() public {
        uint256 amountArc = 1200e18;
        uint256 price = 2e6;

        vm.prank(alice);
        dex.placeBuyOrder(amountArc, price);

        uint256 aliceArcBefore = arc.balanceOf(alice);
        uint256 bobUsdtBefore = usdt.balanceOf(bob);
        uint256 feeUsdtBefore = usdt.balanceOf(feeReceiver);
        uint256 feeArcBefore = arc.balanceOf(feeReceiver);

        uint256 fillAmount = 1100e18;

        vm.prank(bob);
        dex.executeOrder(1, fillAmount);

        // 1100 ARC × 2 USDT = 2200 USDT → tier 1 ($1k–$5k)
        (, uint16 makerBps, uint16 takerBps) = dex.feeTiers(1);

        uint256 usdtTraded = (fillAmount * price) / 1e18;
        uint256 usdtFee = (usdtTraded * makerBps) / 10000;
        uint256 arcFee = (fillAmount * takerBps) / 10000;

        assertEq(arc.balanceOf(alice), aliceArcBefore + (fillAmount - arcFee), "Alice ARC wrong");
        assertEq(usdt.balanceOf(bob), bobUsdtBefore + (usdtTraded - usdtFee), "Bob USDT wrong");
        assertEq(usdt.balanceOf(feeReceiver), feeUsdtBefore + usdtFee, "USDT Fee wrong");
        assertEq(arc.balanceOf(feeReceiver), feeArcBefore + arcFee, "ARC Fee wrong");
    }

    function testPartialFillKeepsOrderActive() public {
        uint256 amountArc = 100e18;
        uint256 price = 1e6;

        vm.prank(alice);
        dex.placeSellOrder(amountArc, price);

        uint256 _partial = 40e18;
        vm.prank(bob);
        dex.executeOrder(1, _partial);

        DexStorage.Order memory ord = dex.getOrder(1);
        assertEq(ord.amount, amountArc - _partial);
        assertEq(uint256(ord.status), uint256(DexStorage.Status.Active));

        vm.prank(charlie);
        dex.executeOrder(1, 60e18);

        ord = dex.getOrder(1);
        assertEq(ord.amount, 0);
        assertEq(uint256(ord.status), uint256(DexStorage.Status.Executed));
    }

    function testCancelOrderRefundsCollateral() public {
        uint256 amountArc = 10e18;
        uint256 price = 3e6;
        vm.prank(alice);
        dex.placeBuyOrder(amountArc, price);

        uint256 aliceUsdtBefore = usdt.balanceOf(alice);
        vm.prank(alice);
        dex.cancelOrder(1);

        uint256 usdtToRefund = (amountArc * price) / 1e18;
        assertEq(usdt.balanceOf(alice), aliceUsdtBefore + usdtToRefund);

        DexStorage.Order memory ord = dex.getOrder(1);
        assertEq(uint256(ord.status), uint256(DexStorage.Status.Canceled));
    }

    /* -------------------------------------------------------------------
       Negative tests, validations, and bug detections
       ------------------------------------------------------------------- */

    function testCannotPlaceZeroAmounts() public {
        vm.prank(alice);
        vm.expectRevert(errSel("InvalidAmounts()"));
        dex.placeSellOrder(0, 1e6);

        vm.prank(alice);
        vm.expectRevert(errSel("InvalidAmounts()"));
        dex.placeBuyOrder(0, 1e6);

        vm.prank(alice);
        vm.expectRevert(errSel("InvalidAmounts()"));
        dex.placeSellOrder(1e18, 0);

        vm.prank(alice);
        vm.expectRevert(errSel("InvalidAmounts()"));
        dex.placeBuyOrder(1e18, 0);
    }

    function testBuyOrderDustRejected() public {
        // 1 wei ARC at any price still produces 0 usdtCollateral — must revert
        vm.prank(alice);
        vm.expectRevert(errSel("InvalidAmounts()"));
        dex.placeBuyOrder(1, 1e6); // (1 * 1e6) / 1e18 == 0
    }

    function testCancelBuyOrderRefundsExactLockedUsdt() public {
        uint256 amountArc = 10e18;
        uint256 price = 3e6;
        uint256 expectedCollateral = (amountArc * price) / 1e18; // 30e6

        vm.prank(alice);
        dex.placeBuyOrder(amountArc, price);

        uint256 aliceBefore = usdt.balanceOf(alice);
        vm.prank(alice);
        dex.cancelOrder(1);

        assertEq(usdt.balanceOf(alice), aliceBefore + expectedCollateral);
    }

    function testGetUserOrdersPagination() public {
        vm.startPrank(alice);
        dex.placeSellOrder(10e18, 1e6); // id 1
        dex.placeSellOrder(10e18, 1e6); // id 2
        dex.placeSellOrder(10e18, 1e6); // id 3
        vm.stopPrank();

        assertEq(dex.getUserOrderCount(alice), 3);

        DexStorage.Order[] memory page1 = dex.getUserOrders(alice, 0, 2);
        assertEq(page1.length, 2);
        assertEq(page1[0].id, 1);
        assertEq(page1[1].id, 2);

        DexStorage.Order[] memory page2 = dex.getUserOrders(alice, 2, 2);
        assertEq(page2.length, 1);
        assertEq(page2[0].id, 3);

        DexStorage.Order[] memory empty = dex.getUserOrders(alice, 10, 5);
        assertEq(empty.length, 0);
    }

    function testCancelSellOrderRefundsArc() public {
        uint256 amountArc = 50e18;
        vm.prank(alice);
        dex.placeSellOrder(amountArc, 2e6);

        uint256 aliceArcBefore = arc.balanceOf(alice);

        vm.prank(alice);
        dex.cancelOrder(1);

        assertEq(arc.balanceOf(alice), aliceArcBefore + amountArc);
        DexStorage.Order memory ord = dex.getOrder(1);
        assertEq(uint256(ord.status), uint256(DexStorage.Status.Canceled));
    }

    function testPartialFillThenCancelBuyOrder() public {
        uint256 amountArc = 100e18;
        uint256 price = 2e6;
        uint256 lockedUsdt = (amountArc * price) / 1e18; // 200e6

        vm.prank(alice);
        dex.placeBuyOrder(amountArc, price);

        // Bob partially fills half
        uint256 fillAmount = 60e18;
        uint256 usdtTraded = (fillAmount * price) / 1e18; // 120e6

        vm.prank(bob);
        dex.executeOrder(1, fillAmount);

        // Alice cancels the remaining portion
        uint256 aliceUsdtBefore = usdt.balanceOf(alice);
        vm.prank(alice);
        dex.cancelOrder(1);

        // Exact remaining locked USDT must be returned (no rounding dust lost)
        uint256 expectedRefund = lockedUsdt - usdtTraded; // 80e6
        assertEq(usdt.balanceOf(alice), aliceUsdtBefore + expectedRefund, "Refund mismatch");

        // Contract should hold no residual USDT from this order
        DexStorage.Order memory ord = dex.getOrder(1);
        assertEq(uint256(ord.status), uint256(DexStorage.Status.Canceled));
        assertEq(ord.amount, amountArc - fillAmount, "Remaining ARC wrong");
    }

    function testFullyExecutedBuyOrderSweepsDust() public {
        // price = 1 forces rounding: floor(1.5e18 * 1 / 1e18) = 1 per fill
        // lockedUsdt = 3, two fills pay 1+1=2, dust=1 → swept to feeReceiver
        vm.prank(alice);
        dex.placeBuyOrder(3e18, 1); // lockedUsdt = 3 wei USDT

        uint256 feeReceiverBefore = usdt.balanceOf(feeReceiver);
        uint256 contractBefore = usdt.balanceOf(address(dex));

        vm.prank(bob);
        dex.executeOrder(1, 15e17); // fill 1: 1.5 ARC
        vm.prank(charlie);
        dex.executeOrder(1, 15e17); // fill 2: 1.5 ARC — fully executes order

        // Contract must hold zero residual USDT from this order
        assertEq(usdt.balanceOf(address(dex)), contractBefore - 3);

        DexStorage.Order memory ord = dex.getOrder(1);
        assertEq(ord.lockedUsdt, 0, "dust not swept");
        assertEq(uint256(ord.status), uint256(DexStorage.Status.Executed));

        // feeReceiver received normal fees (0 at this price scale) plus the 1 wei dust
        assertGe(usdt.balanceOf(feeReceiver), feeReceiverBefore + 1);
    }

    function testFillWithZeroUsdtValueReverts() public {
        // price = 1 (1 wei USDT per 1e18 wei ARC), fill 0.5e18 ARC → usdtTraded = 0 → revert
        vm.prank(alice);
        dex.placeBuyOrder(3e18, 1); // lockedUsdt = 3

        vm.prank(bob);
        vm.expectRevert(errSel("InvalidAmounts()"));
        dex.executeOrder(1, 5e17); // floor(5e17 * 1 / 1e18) = 0

        // Same protection for sell orders: taker gets 0 USDT for their ARC
        vm.prank(alice);
        dex.placeSellOrder(3e18, 1);

        vm.prank(bob);
        vm.expectRevert(errSel("InvalidAmounts()"));
        dex.executeOrder(2, 5e17);
    }

    function testCannotFillOwnOrder() public {
        vm.prank(alice);
        dex.placeSellOrder(50e18, 1e6);

        vm.prank(alice);
        vm.expectRevert(errSel("CannotFillOwnOrder()"));
        dex.executeOrder(1, 10e18);
    }

    function testExecuteInvalidAmount() public {
        vm.prank(alice);
        dex.placeSellOrder(20e18, 1e6);

        vm.prank(bob);
        vm.expectRevert(errSel("InsufficientOrderAmount()"));
        dex.executeOrder(1, 30e18);

        vm.prank(bob);
        vm.expectRevert(errSel("InvalidAmounts()"));
        dex.executeOrder(1, 0);
    }

    function testGetOrderNotFound() public {
        vm.expectRevert(errSel("OrderNotFound()"));
        dex.getOrder(0);

        vm.expectRevert(errSel("OrderNotFound()"));
        dex.getOrder(999);
    }

    function testCancelOnlyMakerAndOnlyActive() public {
        vm.prank(alice);
        dex.placeSellOrder(10e18, 1e6);

        vm.prank(bob);
        vm.expectRevert(errSel("Unauthorized()"));
        dex.cancelOrder(1);

        vm.prank(alice);
        dex.cancelOrder(1);

        vm.prank(alice);
        vm.expectRevert(errSel("OrderNotActive()"));
        dex.cancelOrder(1);
    }

    function testMultiplePartialFillsFromDifferentTakers() public {
        uint256 amountArc = 150e18;
        uint256 price = 1e6;
        vm.prank(alice);
        dex.placeSellOrder(amountArc, price);

        vm.prank(bob);
        dex.executeOrder(1, 50e18);

        vm.prank(charlie);
        dex.executeOrder(1, 70e18);

        address david = address(0xD4D);
        arc.mint(david, 50e18);
        usdt.mint(david, 150e6);
        vm.prank(david);
        arc.approve(address(dex), type(uint256).max);
        vm.prank(david);
        usdt.approve(address(dex), type(uint256).max);

        vm.prank(david);
        dex.executeOrder(1, 30e18);

        DexStorage.Order memory ord = dex.getOrder(1);
        assertEq(ord.amount, 0);
        assertEq(uint256(ord.status), uint256(DexStorage.Status.Executed));
    }

    function testPartialFillExactRemainingWorks() public {
        uint256 amountArc = 80e18;
        uint256 price = 1e6;
        vm.prank(alice);
        dex.placeSellOrder(amountArc, price);

        vm.prank(bob);
        dex.executeOrder(1, 50e18);

        vm.prank(charlie);
        dex.executeOrder(1, 30e18);

        DexStorage.Order memory ord = dex.getOrder(1);
        assertEq(ord.amount, 0);
        assertEq(uint256(ord.status), uint256(DexStorage.Status.Executed));
    }

    function testPartialFillRevertsForInvalidAmounts() public {
        uint256 amountArc = 50e18;
        uint256 price = 1e6;
        vm.prank(alice);
        dex.placeSellOrder(amountArc, price);

        vm.prank(bob);
        vm.expectRevert(errSel("InvalidAmounts()"));
        dex.executeOrder(1, 0);

        vm.prank(bob);
        vm.expectRevert(errSel("InsufficientOrderAmount()"));
        dex.executeOrder(1, 60e18);
    }
}

// ══════════════════════════════════════════════════════════════════════════════
// Constructor validation — DexStorage zero-address and same-token checks
// ══════════════════════════════════════════════════════════════════════════════

contract DexConstructorTest is Test {
    MockToken internal arc;
    MockToken internal usdt;
    address internal feeReceiver = makeAddr("feeReceiver");

    function setUp() public {
        arc = new MockToken(address(this), 0);
        usdt = new MockToken(address(this), 0);
    }

    function test_Constructor_ZeroArcToken_Reverts() public {
        vm.expectRevert(DexErrors.ZeroAddress.selector);
        new Dex(address(0), address(usdt), feeReceiver);
    }

    function test_Constructor_ZeroUsdtToken_Reverts() public {
        vm.expectRevert(DexErrors.ZeroAddress.selector);
        new Dex(address(arc), address(0), feeReceiver);
    }

    function test_Constructor_ZeroFeeReceiver_Reverts() public {
        vm.expectRevert(DexErrors.ZeroAddress.selector);
        new Dex(address(arc), address(usdt), address(0));
    }

    function test_Constructor_SameTokens_Reverts() public {
        vm.expectRevert(DexErrors.SameTokens.selector);
        new Dex(address(arc), address(arc), feeReceiver);
    }
}
