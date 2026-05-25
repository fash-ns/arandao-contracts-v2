// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {Test, console} from "forge-std/Test.sol";
import {Dex} from "../../src/Dex/Dex.sol";
import {DexStorage} from "../../src/Dex/DexCore/DexStorage.sol";
import {MockToken} from "../mocks/MockToken.sol";
import {MockVault} from "../mocks/MockVault.sol";

contract DexTest is Test {
    Dex public dex;
    MockToken public dnm;
    MockToken public dai;
    MockVault public vault;

    address public alice = address(0xA11CE);
    address public bob = address(0xB0B);
    address public charlie = address(0xC11);
    address public feeReceiver = address(0xFEE);
    address public attacker = address(0xBAD);

    // helper to produce custom error selector bytes for expectRevert
    function errSel(string memory sig) internal pure returns (bytes memory) {
        return abi.encodeWithSelector(bytes4(keccak256(bytes(sig))));
    }

    function setUp() public {
        // Deploy mock tokens: DNM and DAI
        dnm = new MockToken(address(this), 100_000_000e18);
        dai = new MockToken(address(this), 100_000_000e18);

        // Deploy mock vault
        vault = new MockVault(1e18);

        // Deploy Dex directly (no owner)
        dex = new Dex(address(dnm), address(dai), feeReceiver, address(vault));

        // Mint tokens to actors
        dnm.mint(alice, 1_000_000e18);
        dnm.mint(bob, 1_000_000e18);
        dnm.mint(charlie, 1_000_000e18);

        dai.mint(alice, 1_000_000e18);
        dai.mint(bob, 1_000_000e18);
        dai.mint(charlie, 1_000_000e18);

        // Preparing approvals
        vm.startPrank(alice);
        dnm.approve(address(dex), type(uint256).max);
        dai.approve(address(dex), type(uint256).max);
        vm.stopPrank();

        vm.startPrank(bob);
        dnm.approve(address(dex), type(uint256).max);
        dai.approve(address(dex), type(uint256).max);
        vm.stopPrank();

        vm.startPrank(charlie);
        dnm.approve(address(dex), type(uint256).max);
        dai.approve(address(dex), type(uint256).max);
        vm.stopPrank();
    }

    /* -------------------------------------------------------------------
       Happy-path & core behavior tests
       ------------------------------------------------------------------- */

    function testPlaceSellAndExecuteFullFill() public {
        // alice places a sell order: sell 100 DNM at price 2 DAI/ DNM
        vm.prank(alice);
        dex.placeSellOrder(100e18, 2e18);

        // order id should be 1
        (,, bool isSell, uint256 amount, uint256 p,) = dex.orders(1);
        assertTrue(isSell);
        assertEq(amount, 100e18);
        assertEq(p, 2e18);

        // bob will execute the order, fully filling amount 100
        // bob must send daiTraded = amount * price / 1e18 = 200 DAI
        uint256 daiTraded = (100e18 * 2e18) / 1e18; // 200e18

        // pre-check balances
        uint256 aliceDaiBefore = dai.balanceOf(alice);
        uint256 bobDnmBefore = dnm.balanceOf(bob);
        uint256 feeDaiBefore = dai.balanceOf(feeReceiver);
        uint256 feeDnmBefore = dnm.balanceOf(feeReceiver);

        vm.prank(bob);
        dex.executeOrder(1, 100e18);

        // Read the applicable fee tier for this volume (tier 0 for small trades)
        (, uint16 makerBps0, uint16 takerBps0) = dex.feeTiers(0);

        uint256 daiFee = (daiTraded * uint256(makerBps0)) / 10000;
        uint256 dnmFee = (100e18 * uint256(takerBps0)) / 10000;

        assertEq(dai.balanceOf(alice), aliceDaiBefore + (daiTraded - daiFee));
        assertEq(dnm.balanceOf(bob), bobDnmBefore + (100e18 - dnmFee));
        assertEq(dai.balanceOf(feeReceiver), feeDaiBefore + daiFee);
        assertEq(dnm.balanceOf(feeReceiver), feeDnmBefore + dnmFee);

        DexStorage.Order memory ord = dex.getOrder(1);
        assertEq(uint256(ord.status), uint256(DexStorage.Status.Executed));
        assertEq(ord.amount, 0);
    }

    function testPlaceBuyAndExecuteFullFill() public {
        console.log("=== Test: Full Fill Buy Order with Fee Accounting ===");

        uint256 amountDNM = 200e18;
        uint256 price = 1e18;

        vm.prank(alice);
        dex.placeBuyOrder(amountDNM, price);

        uint256 aliceDnmBefore = dnm.balanceOf(alice);
        uint256 bobDaiBefore = dai.balanceOf(bob);
        uint256 feeDaiBefore = dai.balanceOf(feeReceiver);
        uint256 feeDnmBefore = dnm.balanceOf(feeReceiver);

        vm.prank(bob);
        dex.executeOrder(1, amountDNM);

        (, uint16 makerBps0, uint16 takerBps0) = dex.feeTiers(0);

        uint256 daiTraded = (amountDNM * price) / 1e18;
        uint256 daiFee = (daiTraded * makerBps0) / 10000;
        uint256 dnmFee = (amountDNM * takerBps0) / 10000;

        assertEq(dnm.balanceOf(alice), aliceDnmBefore + (amountDNM - dnmFee), "Alice DNM wrong");
        assertEq(dai.balanceOf(bob), bobDaiBefore + (daiTraded - daiFee), "Bob DAI wrong");
        assertEq(dai.balanceOf(feeReceiver), feeDaiBefore + daiFee, "DAI Fee wrong");
        assertEq(dnm.balanceOf(feeReceiver), feeDnmBefore + dnmFee, "DNM Fee wrong");

        DexStorage.Order memory ord = dex.getOrder(1);
        assertEq(uint256(ord.status), uint256(DexStorage.Status.Executed));
        assertEq(ord.amount, 0);
    }

    function testPartialFillBuyOrder() public {
        uint256 amountDNM = 1200e18;
        uint256 price = 2e18;

        vm.prank(alice);
        dex.placeBuyOrder(amountDNM, price);

        uint256 aliceDnmBefore = dnm.balanceOf(alice);
        uint256 bobDaiBefore = dai.balanceOf(bob);
        uint256 feeDaiBefore = dai.balanceOf(feeReceiver);
        uint256 feeDnmBefore = dnm.balanceOf(feeReceiver);

        uint256 fillAmount = 1100e18;

        vm.prank(bob);
        dex.executeOrder(1, fillAmount);

        // 1100 DNM × 2 DAI = 2200 DAI → tier 1 ($1k–$5k)
        (, uint16 makerBps, uint16 takerBps) = dex.feeTiers(1);

        uint256 daiTraded = (fillAmount * price) / 1e18;
        uint256 daiFee = (daiTraded * makerBps) / 10000;
        uint256 dnmFee = (fillAmount * takerBps) / 10000;

        assertEq(dnm.balanceOf(alice), aliceDnmBefore + (fillAmount - dnmFee), "Alice DNM wrong");
        assertEq(dai.balanceOf(bob), bobDaiBefore + (daiTraded - daiFee), "Bob DAI wrong");
        assertEq(dai.balanceOf(feeReceiver), feeDaiBefore + daiFee, "DAI Fee wrong");
        assertEq(dnm.balanceOf(feeReceiver), feeDnmBefore + dnmFee, "DNM Fee wrong");
    }

    function testPartialFillKeepsOrderActive() public {
        uint256 amountDNM = 100e18;
        uint256 price = 1e18;

        vm.prank(alice);
        dex.placeSellOrder(amountDNM, price);

        uint256 _partial = 40e18;
        vm.prank(bob);
        dex.executeOrder(1, _partial);

        DexStorage.Order memory ord = dex.getOrder(1);
        assertEq(ord.amount, amountDNM - _partial);
        assertEq(uint256(ord.status), uint256(DexStorage.Status.Active));

        vm.prank(charlie);
        dex.executeOrder(1, 60e18);

        ord = dex.getOrder(1);
        assertEq(ord.amount, 0);
        assertEq(uint256(ord.status), uint256(DexStorage.Status.Executed));
    }

    function testCancelOrderRefundsCollateral() public {
        uint256 amountDNM = 10e18;
        uint256 price = 3e18;
        vm.prank(alice);
        dex.placeBuyOrder(amountDNM, price);

        uint256 aliceDaiBefore = dai.balanceOf(alice);
        vm.prank(alice);
        dex.cancelOrder(1);

        uint256 daiToRefund = (amountDNM * price) / 1e18;
        assertEq(dai.balanceOf(alice), aliceDaiBefore + daiToRefund);

        DexStorage.Order memory ord = dex.getOrder(1);
        assertEq(uint256(ord.status), uint256(DexStorage.Status.Canceled));
    }

    /* -------------------------------------------------------------------
       Negative tests, validations, and bug detections
       ------------------------------------------------------------------- */

    function testCannotPlaceZeroAmounts() public {
        vm.prank(alice);
        vm.expectRevert(errSel("InvalidAmounts()"));
        dex.placeSellOrder(0, 1e18);

        vm.prank(alice);
        vm.expectRevert(errSel("InvalidAmounts()"));
        dex.placeBuyOrder(0, 1e18);

        vm.prank(alice);
        vm.expectRevert(errSel("PriceOutOfRange()"));
        dex.placeSellOrder(1e18, 0);

        vm.prank(alice);
        vm.expectRevert(errSel("PriceOutOfRange()"));
        dex.placeBuyOrder(1e18, 0);
    }

    function testCannotFillOwnOrder() public {
        vm.prank(alice);
        dex.placeSellOrder(50e18, 1e18);

        vm.prank(alice);
        vm.expectRevert(errSel("CannotFillOwnOrder()"));
        dex.executeOrder(1, 10e18);
    }

    function testExecuteInvalidAmount() public {
        vm.prank(alice);
        dex.placeSellOrder(20e18, 1e18);

        vm.prank(bob);
        vm.expectRevert(errSel("InsufficientOrderAmount()"));
        dex.executeOrder(1, 30e18);

        vm.prank(bob);
        vm.expectRevert(errSel("InvalidAmounts()"));
        dex.executeOrder(1, 0);
    }

    function testUpdateFeeRecipientOnce() public {
        assertEq(address(dex.feeReceiver()), feeReceiver);

        // attacker cannot change
        vm.prank(attacker);
        vm.expectRevert(errSel("Unauthorized()"));
        dex.updateFeeRecipient(attacker);

        // feeReceiver changes to attacker
        vm.prank(feeReceiver);
        dex.updateFeeRecipient(attacker);
        assertEq(address(dex.feeReceiver()), attacker);

        // second change reverts
        vm.prank(attacker);
        vm.expectRevert(errSel("FeeRecipientAlreadyChanged()"));
        dex.updateFeeRecipient(alice);
    }

    function testGetOrderNotFound() public {
        vm.expectRevert(errSel("OrderNotFound()"));
        dex.getOrder(0);

        vm.expectRevert(errSel("OrderNotFound()"));
        dex.getOrder(999);
    }

    function testCancelOnlyMakerAndOnlyActive() public {
        vm.prank(alice);
        dex.placeSellOrder(10e18, 1e18);

        vm.prank(bob);
        vm.expectRevert(errSel("Unauthorized()"));
        dex.cancelOrder(1);

        vm.prank(alice);
        dex.cancelOrder(1);

        vm.prank(alice);
        vm.expectRevert(errSel("OrderNotActive()"));
        dex.cancelOrder(1);
    }

    function testExecuteSellOrderFailsIfVaultPriceOutOfRange() public {
        uint256 amountDNM = 100e18;
        uint256 orderPrice = 2e18;

        vm.prank(alice);
        dex.placeSellOrder(amountDNM, orderPrice);

        vault.setPrice(4e18);

        vm.prank(bob);
        vm.expectRevert(errSel("PriceOutOfRange()"));
        dex.executeOrder(1, amountDNM);
    }

    function testExecuteBuyOrderFailsIfVaultPriceOutOfRange() public {
        uint256 amountDNM = 50e18;
        uint256 orderPrice = 2e18;

        vm.prank(alice);
        dex.placeBuyOrder(amountDNM, orderPrice);

        vault.setPrice(4e18);

        vm.prank(bob);
        vm.expectRevert(errSel("PriceOutOfRange()"));
        dex.executeOrder(1, amountDNM);
    }

    function testMultiplePartialFillsFromDifferentTakers() public {
        uint256 amountDNM = 150e18;
        uint256 price = 1e18;
        vm.prank(alice);
        dex.placeSellOrder(amountDNM, price);

        vm.prank(bob);
        dex.executeOrder(1, 50e18);

        vm.prank(charlie);
        dex.executeOrder(1, 70e18);

        address david = address(0xD4D);
        dnm.mint(david, 50e18);
        dai.mint(david, 150e18);
        vm.prank(david);
        dnm.approve(address(dex), type(uint256).max);
        vm.prank(david);
        dai.approve(address(dex), type(uint256).max);

        vm.prank(david);
        dex.executeOrder(1, 30e18);

        DexStorage.Order memory ord = dex.getOrder(1);
        assertEq(ord.amount, 0);
        assertEq(uint256(ord.status), uint256(DexStorage.Status.Executed));
    }

    function testPartialFillExactRemainingWorks() public {
        uint256 amountDNM = 80e18;
        uint256 price = 1e18;
        vm.prank(alice);
        dex.placeSellOrder(amountDNM, price);

        vm.prank(bob);
        dex.executeOrder(1, 50e18);

        vm.prank(charlie);
        dex.executeOrder(1, 30e18);

        DexStorage.Order memory ord = dex.getOrder(1);
        assertEq(ord.amount, 0);
        assertEq(uint256(ord.status), uint256(DexStorage.Status.Executed));
    }

    function testPartialFillRevertsForInvalidAmounts() public {
        uint256 amountDNM = 50e18;
        uint256 price = 1e18;
        vm.prank(alice);
        dex.placeSellOrder(amountDNM, price);

        vm.prank(bob);
        vm.expectRevert(errSel("InvalidAmounts()"));
        dex.executeOrder(1, 0);

        vm.prank(bob);
        vm.expectRevert(errSel("InsufficientOrderAmount()"));
        dex.executeOrder(1, 60e18);
    }
}
