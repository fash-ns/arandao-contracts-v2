// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {Test, console} from "forge-std/Test.sol";
import {Dex} from "../../src/Dex/Dex.sol";
import {DexStorage} from "../../src/Dex/DexCore/DexStorage.sol";
import {DexErrors} from "../../src/Dex/DexCore/DexErrors.sol";
import {MockToken} from "../mocks/MockToken.sol";
import {MockVault} from "../mocks/MockVault.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {UUPSUpgradeable} from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import {ERC1967Utils} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Utils.sol";

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
    address public owner = makeAddr("owner");

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

        // Deploy Dex implementation
        Dex dexImplementation = new Dex();

        // Deploy UUPS proxy (ERC1967)
        ERC1967Proxy proxy = new ERC1967Proxy(
            address(dexImplementation),
            abi.encodeWithSelector(
                Dex.initialize.selector,
                owner, // initialOwner
                address(dnm), // DNM token
                address(dai), // DAI token
                feeReceiver, // fee receiver
                address(vault) // vault
            )
        );

        // Proxy is now the live Dex
        dex = Dex(address(proxy));

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
        // alice places sell order
        vm.prank(alice);
        dex.placeSellOrder(100e18, 2e18);

        // order id should be 1
        (,, bool isSell, uint256 amount, uint256 p,) = dex.orders(1); // public mapping accessible
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

        // perform execute
        vm.prank(bob);
        dex.executeOrder(1, 100e18);

        // Read the applicable fee tier for this volume.
        // For small trades this should be feeTiers[0]; we read tier0 for determinism.
        (, uint16 makerBps0, uint16 takerBps0) = dex.feeTiers(0);

        // calculate fees using on-chain bps values (avoids hardcoding)
        uint256 daiFee = (daiTraded * uint256(makerBps0)) / 10000;
        uint256 dnmFee = (100e18 * uint256(takerBps0)) / 10000;

        uint256 expectedMakerDai = daiTraded - daiFee;
        uint256 expectedTakerDnm = 100e18 - dnmFee;

        // Post balances assertions
        assertEq(dai.balanceOf(alice), aliceDaiBefore + expectedMakerDai);
        assertEq(dnm.balanceOf(bob), bobDnmBefore + expectedTakerDnm);
        assertEq(dai.balanceOf(feeReceiver), feeDaiBefore + daiFee);
        assertEq(dnm.balanceOf(feeReceiver), feeDnmBefore + dnmFee);

        // Order should be executed (status = Executed)
        DexStorage.Order memory ord = dex.getOrder(1);
        assertEq(uint256(ord.status), uint256(DexStorage.Status.Executed));
        assertEq(ord.amount, 0);
    }

    function testPlaceBuyAndExecuteFullFill() public {
        console.log("=== Test: Full Fill Buy Order with Fee Accounting ===");

        uint256 amountDNM = 200e18;
        uint256 price = 1e18;

        console.log("Placing Buy Order: amountDNM =", amountDNM);
        console.log("Price (DAI per DNM) =", price);

        vm.prank(alice);
        dex.placeBuyOrder(amountDNM, price);

        // Pre-balances
        uint256 aliceDnmBefore = dnm.balanceOf(alice);
        uint256 bobDaiBefore = dai.balanceOf(bob);
        uint256 feeDaiBefore = dai.balanceOf(feeReceiver);
        uint256 feeDnmBefore = dnm.balanceOf(feeReceiver);

        console.log("Balances BEFORE execution");
        console.log("  Alice DNM:", aliceDnmBefore);
        console.log("  Bob DAI:", bobDaiBefore);
        console.log("  FeeReceiver DAI:", feeDaiBefore);
        console.log("  FeeReceiver DNM:", feeDnmBefore);

        // Bob executes (fully filling)
        vm.prank(bob);
        dex.executeOrder(1, amountDNM);

        // Tier Fee Info
        (, uint16 makerBps0, uint16 takerBps0) = dex.feeTiers(0);
        console.log("Fee Tier Used (Tier 0)");
        console.log("  Maker fee Bps:", makerBps0);
        console.log("  Taker fee Bps:", takerBps0);

        uint256 daiTraded = (amountDNM * price) / 1e18;
        console.log("DAI traded:", daiTraded);

        uint256 daiFee = (daiTraded * makerBps0) / 10000;
        uint256 dnmFee = (amountDNM * takerBps0) / 10000;

        console.log("Fees");
        console.log("  Maker fee (DAI) =", daiFee);
        console.log("  Taker fee (DNM) =", dnmFee);

        uint256 expectedMakerDnm = amountDNM - dnmFee;
        uint256 expectedTakerDai = daiTraded - daiFee;

        console.log("Expected Transfer Results");
        console.log("  Alice receives DNM:", expectedMakerDnm);
        console.log("  Bob receives DAI:", expectedTakerDai);

        // Assertions
        console.log("Balances AFTER execution");
        console.log("  Alice DNM:", dnm.balanceOf(alice));
        console.log("  Bob DAI:", dai.balanceOf(bob));
        console.log("  FeeReceiver DAI:", dai.balanceOf(feeReceiver));
        console.log("  FeeReceiver DNM:", dnm.balanceOf(feeReceiver));

        assertEq(dnm.balanceOf(alice), aliceDnmBefore + expectedMakerDnm, "Alice DNM wrong");
        assertEq(dai.balanceOf(bob), bobDaiBefore + expectedTakerDai, "Bob DAI wrong");

        assertEq(dai.balanceOf(feeReceiver), feeDaiBefore + daiFee, "DAI Fee wrong");
        assertEq(dnm.balanceOf(feeReceiver), feeDnmBefore + dnmFee, "DNM Fee wrong");

        DexStorage.Order memory ord = dex.getOrder(1);
        console.log("Order Status =", uint256(ord.status));
        console.log("Order Remaining Amount =", ord.amount);

        assertEq(uint256(ord.status), uint256(DexStorage.Status.Executed));
        assertEq(ord.amount, 0);

        console.log("=== Test Completed Successfully ===");
    }

    function testPartialFillBuyOrder() public {
        console.log("=== Test: Partial Fill Buy Order with Tier 1 Fees ===");

        uint256 amountDNM = 1200e18;
        uint256 price = 2e18;

        vm.prank(alice);
        dex.placeBuyOrder(amountDNM, price);

        // Pre balances
        uint256 aliceDnmBefore = dnm.balanceOf(alice);
        uint256 bobDaiBefore = dai.balanceOf(bob);
        uint256 feeDaiBefore = dai.balanceOf(feeReceiver);
        uint256 feeDnmBefore = dnm.balanceOf(feeReceiver);

        console.log("Balances BEFORE execution");
        console.log("  Alice DNM:", aliceDnmBefore);
        console.log("  Bob DAI:", bobDaiBefore);
        console.log("  FeeReceiver DAI:", feeDaiBefore);
        console.log("  FeeReceiver DNM:", feeDnmBefore);

        // Bob performs partial fill: 1100 DNM
        uint256 fillAmount = 1100e18;

        vm.prank(bob);
        dex.executeOrder(1, fillAmount);

        // Read tier info (should use tier 1)
        (, uint16 makerBps, uint16 takerBps) = dex.feeTiers(1);

        console.log("Fee Tier Used (Tier 1)");
        console.log("  Maker fee Bps:", makerBps);
        console.log("  Taker fee Bps:", takerBps);

        uint256 daiTraded = (fillAmount * price) / 1e18;
        console.log("DAI traded:", daiTraded);

        // fees
        uint256 daiFee = (daiTraded * makerBps) / 10000;
        uint256 dnmFee = (fillAmount * takerBps) / 10000;

        console.log("Fees");
        console.log("  Maker fee (DAI) =", daiFee);
        console.log("  Taker fee (DNM) =", dnmFee);

        console.log("Expected Results");
        console.log("  Alice receives DNM:", (fillAmount - dnmFee));
        console.log("  Bob receives DAI:", (daiTraded - daiFee));
        console.log("  Remaining Order DNM:", amountDNM - fillAmount);

        // Assertions
        assertEq(dnm.balanceOf(alice), aliceDnmBefore + (fillAmount - dnmFee), "Alice DNM wrong");
        assertEq(dai.balanceOf(bob), bobDaiBefore + (daiTraded - daiFee), "Bob DAI wrong");

        assertEq(dai.balanceOf(feeReceiver), feeDaiBefore + daiFee, "DAI Fee wrong");
        assertEq(dnm.balanceOf(feeReceiver), feeDnmBefore + dnmFee, "DNM Fee wrong");
    }

    function testPartialFillKeepsOrderActive() public {
        // alice sells 100 DNM at price 1e18
        uint256 amountDNM = 100e18;
        uint256 price = 1e18;

        vm.prank(alice);
        dex.placeSellOrder(amountDNM, price);

        // bob partially fills 40 DNM
        uint256 _partial = 40e18;
        vm.prank(bob);
        dex.executeOrder(1, _partial);

        DexStorage.Order memory ord = dex.getOrder(1);
        assertEq(ord.amount, amountDNM - _partial);
        assertEq(uint256(ord.status), uint256(DexStorage.Status.Active));

        // charlie fills the remaining 60
        vm.prank(charlie);
        dex.executeOrder(1, 60e18);

        ord = dex.getOrder(1);
        assertEq(ord.amount, 0);
        assertEq(uint256(ord.status), uint256(DexStorage.Status.Executed));
    }

    function testCancelOrderRefundsCollateral() public {
        // alice places buy order: buy 10 DNM at price 3 DAI/ DNM -> collateral = 30 DAI
        uint256 amountDNM = 10e18;
        uint256 price = 3e18;
        vm.prank(alice);
        dex.placeBuyOrder(amountDNM, price);

        // cancel
        uint256 aliceDaiBefore = dai.balanceOf(alice);
        vm.prank(alice);
        dex.cancelOrder(1);

        // after cancel she should get 30 DAI back
        uint256 daiToRefund = (amountDNM * price) / 1e18;
        assertEq(dai.balanceOf(alice), aliceDaiBefore + daiToRefund);

        DexStorage.Order memory ord = dex.getOrder(1);
        assertEq(uint256(ord.status), uint256(DexStorage.Status.Canceled));
    }

    /* -------------------------------------------------------------------
       Negative tests, validations, and bug detections
       ------------------------------------------------------------------- */

    function testCannotPlaceZeroAmounts() public {
        // amount == 0 with valid price => InvalidAmounts()
        vm.prank(alice);
        vm.expectRevert(errSel("InvalidAmounts()"));
        dex.placeSellOrder(0, 1e18);

        vm.prank(alice);
        vm.expectRevert(errSel("InvalidAmounts()"));
        dex.placeBuyOrder(0, 1e18);

        // price == 0 should revert PriceOutOfRange() (modifier or internal check)
        vm.prank(alice);
        vm.expectRevert(errSel("PriceOutOfRange()"));
        dex.placeSellOrder(1e18, 0);

        vm.prank(alice);
        vm.expectRevert(errSel("PriceOutOfRange()"));
        dex.placeBuyOrder(1e18, 0);
    }

    function testCannotFillOwnOrder() public {
        // alice places sell order
        vm.prank(alice);
        dex.placeSellOrder(50e18, 1e18);

        vm.prank(alice);
        vm.expectRevert(errSel("CannotFillOwnOrder()"));
        dex.executeOrder(1, 10e18);
    }

    function testExecuteInvalidAmount() public {
        // alice sells 20 DNM
        vm.prank(alice);
        dex.placeSellOrder(20e18, 1e18);

        // bob tries to execute more than order.amount
        vm.prank(bob);
        vm.expectRevert(errSel("InsufficientOrderAmount()"));
        dex.executeOrder(1, 30e18);

        // executing zero should revert InvalidAmounts()
        vm.prank(bob);
        vm.expectRevert(errSel("InvalidAmounts()"));
        dex.executeOrder(1, 0);
    }

    function testUpdateFeeRecipientAnyoneCanChangeOnce() public {
        // Initial is feeReceiver (set in setUp)
        assertEq(address(dex.feeReceiver()), feeReceiver);

        // attacker tries to change -> Unauthorized()
        vm.prank(attacker);
        vm.expectRevert(errSel("Unauthorized()"));
        dex.updateFeeRecipient(attacker);

        // feeReceiver changes to attacker
        vm.prank(feeReceiver);
        dex.updateFeeRecipient(attacker);
        assertEq(address(dex.feeReceiver()), attacker);

        // further attempts should revert with FeeRecipientAlreadyChanged()
        vm.prank(alice);
        vm.expectRevert(errSel("FeeRecipientAlreadyChanged()"));
        dex.updateFeeRecipient(alice);
    }

    function testGetOrderNotFound() public {
        // requesting order 0 or >= nextOrderId should revert OrderNotFound()
        vm.expectRevert(errSel("OrderNotFound()"));
        dex.getOrder(0);

        vm.expectRevert(errSel("OrderNotFound()"));
        dex.getOrder(999);
    }

    function testCancelOnlyMakerAndOnlyActive() public {
        // alice places sell order
        vm.prank(alice);
        dex.placeSellOrder(10e18, 1e18);

        // bob tries to cancel -> unauthorized
        vm.prank(bob);
        vm.expectRevert(errSel("Unauthorized()"));
        dex.cancelOrder(1);

        // alice cancels ok
        vm.prank(alice);
        dex.cancelOrder(1);

        // cancel again -> not active
        vm.prank(alice);
        vm.expectRevert(errSel("OrderNotActive()"));
        dex.cancelOrder(1);
    }

    function testExecuteSellOrderFailsIfVaultPriceOutOfRange() public {
        // initial price from vault = 1e18 (set in setup)
        // alice places a sell order at price 2 DAI
        uint256 amountDNM = 100e18;
        uint256 orderPrice = 2e18;

        vm.prank(alice);
        dex.placeSellOrder(amountDNM, orderPrice);

        // Now simulate big price change in vault: 4 DAI
        vault.setPrice(4e18);

        // Now bob tries to fill order at old price (2) which is out of range relative to 4
        vm.prank(bob);
        vm.expectRevert(errSel("PriceOutOfRange()"));
        dex.executeOrder(1, amountDNM);
    }

    function testExecuteBuyOrderFailsIfVaultPriceOutOfRange() public {
        // initial price from vault = 1e18
        // alice places a buy order at price 2 DAI
        uint256 amountDNM = 50e18;
        uint256 orderPrice = 2e18;

        vm.prank(alice);
        dex.placeBuyOrder(amountDNM, orderPrice);

        // Price skyrockets in vault to 4
        vault.setPrice(4e18);

        // Now bob tries to execute order at old price (2)
        vm.prank(bob);
        vm.expectRevert(errSel("PriceOutOfRange()"));
        dex.executeOrder(1, amountDNM);
    }

    function testMultiplePartialFillsFromDifferentTakers() public {
        uint256 amountDNM = 150e18;
        uint256 price = 1e18;
        vm.prank(alice);
        dex.placeSellOrder(amountDNM, price);

        // Bob fills 50
        vm.prank(bob);
        dex.executeOrder(1, 50e18);

        // Charlie fills 70
        vm.prank(charlie);
        dex.executeOrder(1, 70e18);

        // Alice fills remaining via another address (simulate)
        address david = address(0xD4D);
        dnm.mint(david, 50e18);
        vm.prank(david);
        dnm.approve(address(dex), type(uint256).max);
        dai.mint(david, 150e18);
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

        // Fill partial 50 DNM
        vm.prank(bob);
        dex.executeOrder(1, 50e18);

        // Fill exact remaining 30 DNM
        vm.prank(charlie);
        dex.executeOrder(1, 30e18);

        DexStorage.Order memory ord = dex.getOrder(1);
        assertEq(ord.amount, 0);
        assertEq(uint256(ord.status), uint256(DexStorage.Status.Executed));
    }

    function testPartialFillRevertsForInvalidAmounts() public {
        // Place sell order
        uint256 amountDNM = 50e18;
        uint256 price = 1e18;
        vm.prank(alice);
        dex.placeSellOrder(amountDNM, price);

        // zero fill should revert
        vm.prank(bob);
        vm.expectRevert(errSel("InvalidAmounts()"));
        dex.executeOrder(1, 0);

        // fill more than remaining should revert
        vm.prank(bob);
        vm.expectRevert(errSel("InsufficientOrderAmount()"));
        dex.executeOrder(1, 60e18);
    }

    function testUpgradeBeforeDeadline() public {
        // Deploy a new implementation
        Dex newImplementation = new Dex();

        // Ensure upgrade works before deadline
        vm.prank(owner); // owner is correct authority
        dex.upgradeToAndCall(address(newImplementation), "");

        // Verify that the implementation address actually changed
        address currentImpl = _getImplementation(address(dex));
        assertEq(currentImpl, address(newImplementation), "Upgrade failed before deadline");
    }

    function testUpgradeFailsAfterDeadline() public {
        // Move time forward beyond deadline (default 90 days)
        vm.warp(block.timestamp + 91 days);

        Dex newImplementation = new Dex();

        // Must revert upgrade attempt
        vm.prank(owner);
        vm.expectRevert("Upgrade deadline has passed");
        dex.upgradeToAndCall(address(newImplementation), "");
    }

    function testUpgradeFailsIfNotOwner() public {
        Dex newImplementation = new Dex();

        // Attempt upgrade from non-owner
        vm.prank(alice);
        vm.expectRevert();
        dex.upgradeToAndCall(address(newImplementation), "");
    }

    // Utility: Read proxy's implementation slot
    function _getImplementation(address proxy) internal view returns (address) {
        bytes32 slot = ERC1967Utils.IMPLEMENTATION_SLOT;
        return address(uint160(uint256(vm.load(proxy, slot))));
    }
}
