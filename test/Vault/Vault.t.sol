// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import {Test} from "forge-std/Test.sol";
import {MockToken} from "../mocks/MockToken.sol";
import {MultiAssetVault} from "../../src/Vault/Vault.sol";
import {VaultStorage} from "../../src/Vault/VaultCore/VaultStorage.sol";
import {PriceFeed} from "../../src/Vault/VaultCore/PriceFeed.sol";
import {MockV3Aggregator} from "../mocks/MockAggregator.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {MockRouter} from "../mocks/MockRouter.sol";

contract MultiAssetVaultTest is Test {
    MockToken internal paxg;
    MockToken internal dai;
    MockToken internal wbtc;
    MockToken internal usdc;
    MockToken internal dnm;

    MockV3Aggregator internal paxgUsdFeed;
    MockV3Aggregator internal wbtcUsdFeed;
    MockV3Aggregator internal daiUsdFeed;

    MultiAssetVault internal vault;
    PriceFeed internal feed;
    MockRouter internal mockRouter;

    address internal owner = makeAddr("owner");
    address internal user = makeAddr("user");
    address internal admin1 = makeAddr("admin1");
    address internal admin2 = makeAddr("admin2");
    address internal admin3 = makeAddr("admin3");
    address internal coreContract = makeAddr("core");
    address internal feeReceiver = makeAddr("feeReceiver");
    address internal uniswapQuoter = makeAddr("quoter");

    /// --------------------
    /// Setup
    /// --------------------
    function setUp() public {
        vm.startPrank(owner);

        // Deploy tokens
        paxg = new MockToken(user, 1e25);
        dai = new MockToken(user, 1e25);
        wbtc = new MockToken(user, 1e25);
        usdc = new MockToken(user, 1e25);
        dnm = new MockToken(address(this), 0);

        // Chainlink mocks
        paxgUsdFeed = new MockV3Aggregator(8, 3000e8);
        wbtcUsdFeed = new MockV3Aggregator(8, 100000e8);
        daiUsdFeed = new MockV3Aggregator(8, 1e8);

        // PriceFeed
        feed = new PriceFeed(address(paxgUsdFeed), address(wbtcUsdFeed), address(daiUsdFeed), 8);

        // Router
        mockRouter = new MockRouter();

        // Vault
        VaultStorage.InitParams memory params = VaultStorage.InitParams({
            dai: address(dai),
            paxg: address(paxg),
            wbtc: address(wbtc),
            usdc: address(usdc),
            arc: address(dnm),
            priceFeed: address(feed),
            coreContract: coreContract,
            uniswapRouter: address(mockRouter),
            uniswapQuoter: uniswapQuoter,
            initalOwner: admin1,
            feeReceiver: feeReceiver
        });

        vault = new MultiAssetVault(params);

        vm.stopPrank();

        // Set fees: tier 0 = 1%, tier 1 = 2%, tier 2 = 3%
        vm.prank(admin1);
        vault.addFeeTier(100, 0);
        vm.prank(admin1);
        vault.addFeeTier(200, 500e18);
        vm.prank(admin1);
        vault.addFeeTier(300, 1000e18);
    }

    /// --------------------
    /// PriceFeed Tests
    /// --------------------
    function testPriceFeedPaxgAndWbtc() public view {
        uint256 paxgInDai = feed.getPaxgInDai();
        uint256 expectedPaxg = 3000 * 1e18;
        assertEq(paxgInDai, expectedPaxg);

        uint256 wbtcInDai = feed.getWbtcInDai();
        uint256 expectedWbtc = 100000 * 1e18;
        assertEq(wbtcInDai, expectedWbtc);
    }

    /// --------------------
    /// Vault Logic Tests
    /// --------------------
    function testVaultGetPriceWhenNoDnmSupply() public view {
        uint256 price = vault.getPrice();
        assertEq(price, 1e18);
    }

    function testEmergencyWithdrawRestrictedThenAllowed() public {
        vm.prank(admin1);
        vm.expectRevert(bytes("Emergency withdrawal restricted during grace period"));
        vault.emergencyWithdraw();

        vm.warp(block.timestamp + 91 days);
        vm.prank(admin1);
        vault.emergencyWithdraw(); // should not revert
    }

    function testWithdrawDaiByCoreWhenSufficientBalance() public {
        uint256 amount = 1e18;

        vm.startPrank(user);
        dai.transfer(address(vault), amount);
        vm.stopPrank();

        uint256 vaultDaiBefore = dai.balanceOf(address(vault));
        assertEq(vaultDaiBefore, amount);

        vm.prank(coreContract);
        vault.withdrawDai(amount);

        assertEq(dai.balanceOf(address(vault)), 0);
        assertEq(dai.balanceOf(coreContract), amount);
    }

    /// --------------------
    /// Deposit / Redeem Tests
    /// --------------------
    function testDepositSplitsIntoAssets() public {
        vm.prank(admin1);
        vault.updateSwapEnabled(false); // disable swaps for testing

        uint256 depositAmount = 1000e18;

        vm.startPrank(user);
        dai.approve(address(vault), depositAmount);
        vault.deposit(depositAmount);
        vm.stopPrank();

        assertEq(dai.balanceOf(address(vault)), (depositAmount));
    }

    function testRedeemTransfersDAIAndFee() public {
        uint256 balanceBefore = dai.balanceOf(user);
        uint256 depositAmount = 1000e18;

        // Step 0: Make sure the vault has DAI
        dai.mint(address(vault), depositAmount);

        // Step 1: Mint DNM for the user to simulate supply
        dnm.mint(user, depositAmount);
        assertEq(dnm.totalSupply(), depositAmount); // sanity check

        // Step 2: User approves and redeems DNM
        vm.startPrank(user);
        dnm.approve(address(vault), depositAmount);
        vault.redeem(depositAmount);
        vm.stopPrank();

        // Step 3: Calculate expected fee based on tiers
        // depositAmount = 1000e18 -> should pick tier 2 = 3%
        uint256 expectedFee = (depositAmount * 3) / 100;
        uint256 expectedNet = depositAmount - expectedFee;

        assertEq(dai.balanceOf(user) - balanceBefore, expectedNet);
        assertEq(dai.balanceOf(feeReceiver), expectedFee);
    }

    function testFeeTiersAppliedCorrectly() public {
        uint256 lastUserBalance = dai.balanceOf(user);

        // Case 1: amount below tier1 floor -> tier0 = 1%
        uint256 amount1 = 100e18;
        dai.mint(address(vault), amount1);
        dnm.mint(user, amount1);

        vm.startPrank(user);
        dnm.approve(address(vault), amount1);
        vault.redeem(amount1);
        vm.stopPrank();

        uint256 expectedFee1 = (amount1 * 1) / 100;
        uint256 expectedNet1 = amount1 - expectedFee1;
        assertEq(dai.balanceOf(user) - lastUserBalance, expectedNet1);
        assertEq(dai.balanceOf(feeReceiver), expectedFee1);

        // Case 2: amount between tier1 and tier2 -> tier1 = 2%
        uint256 amount2 = 700e18;
        lastUserBalance = dai.balanceOf(user);
        dai.mint(address(vault), amount2);
        dnm.mint(user, amount2);

        vm.startPrank(user);
        dnm.approve(address(vault), amount2);
        vault.redeem(amount2);
        vm.stopPrank();

        uint256 expectedFee2 = (amount2 * 2) / 100;
        uint256 expectedNet2 = amount2 - expectedFee2;
        assertEq(dai.balanceOf(user) - lastUserBalance, expectedNet2);
        assertEq(dai.balanceOf(feeReceiver), expectedFee1 + expectedFee2);

        // Case 3: amount >= tier2 floor -> tier2 = 3%
        uint256 amount3 = 1200e18;
        lastUserBalance = dai.balanceOf(user);
        dai.mint(address(vault), amount3);
        dnm.mint(user, amount3);

        vm.startPrank(user);
        dnm.approve(address(vault), amount3);
        vault.redeem(amount3);
        vm.stopPrank();

        uint256 expectedFee3 = (amount3 * 3) / 100;
        uint256 expectedNet3 = amount3 - expectedFee3;
        assertEq(dai.balanceOf(user) - lastUserBalance, expectedNet3);
        assertEq(dai.balanceOf(feeReceiver), expectedFee1 + expectedFee2 + expectedFee3);
    }

    /// --------------------
    /// Additional Vault Tests
    /// --------------------

    // function testDepositWithSwapEnabled() public {
    //     vm.prank(admin1);
    //     vault.updateSwapEnabled(true); // enable swaps

    //     uint256 depositAmount = 1000e18;
    //     uint256 daiBefore = dai.balanceOf(address(vault));
    //     uint256 paxgBefore = paxg.balanceOf(address(vault));
    //     uint256 wbtcBefore = wbtc.balanceOf(address(vault));

    //     vm.startPrank(user);
    //     dai.approve(address(vault), depositAmount);
    //     vault.deposit(depositAmount);
    //     vm.stopPrank();

    //     // With swap enabled, DAI stays 40%, 30% swapped to PAXG, 30% swapped to WBTC
    //     assertEq(dai.balanceOf(address(vault)), daiBefore + (depositAmount * 40) / 100);
    //     assertEq(paxg.balanceOf(address(vault)), paxgBefore + (depositAmount * 30) / 100);
    //     assertEq(wbtc.balanceOf(address(vault)), wbtcBefore + (depositAmount * 30) / 100);
    // }

    function testDepositZeroReverts() public {
        vm.startPrank(user);
        vm.expectRevert(bytes("Deposit amount must be > 0"));
        vault.deposit(0);
        vm.stopPrank();
    }

    function testRedeemZeroArcReverts() public {
        vm.startPrank(user);
        vm.expectRevert(bytes("Cannot redeem from an empty vault"));
        vault.redeem(1e18);
        vm.stopPrank();
    }

    function testEmergencyWithdrawAccessControl() public {
        vm.prank(user);
        vm.expectRevert();
        vault.emergencyWithdraw();
    }

    function testEmergencyWithdrawAfterGracePeriod() public {
        vm.warp(block.timestamp + 91 days);
        uint256 daiBalance = dai.balanceOf(address(vault));
        uint256 paxgBalance = paxg.balanceOf(address(vault));
        uint256 wbtcBalance = wbtc.balanceOf(address(vault));

        vm.prank(admin1);
        vault.emergencyWithdraw();

        // All vault assets should be transferred to admin
        assertEq(dai.balanceOf(admin1), daiBalance);
        assertEq(paxg.balanceOf(admin1), paxgBalance);
        assertEq(wbtc.balanceOf(admin1), wbtcBalance);
    }

    function testWithdrawDaiByNonCoreReverts() public {
        vm.prank(user);
        vm.expectRevert(bytes("Not authorized: not core"));
        vault.withdrawDai(1e18);
    }

    function testPauseAndUnpause() public {
        // Pause vault
        vm.prank(admin1);
        vault.updateSwapEnabled(false);

        vm.prank(admin1);
        vault.pause();

        vm.startPrank(user);
        dai.approve(address(vault), 1e18);
        vm.expectRevert();
        vault.deposit(1e18);
        vm.expectRevert();
        vault.redeem(1e18);
        vm.stopPrank();

        // Unpause vault
        vm.prank(admin1);
        vault.unpause();

        vm.startPrank(user);
        dai.approve(address(vault), 1e18);
        vault.deposit(1e18); // Should succeed
        vm.stopPrank();
    }

    function testFeeTierBoundaries() public {
        uint256 amountBelowTier1 = 100e18;
        uint256 amountOnTier1Floor = 500e18;
        uint256 amountAboveTier2 = 1200e18;

        // Mint DAI and DNM
        dai.mint(address(vault), amountBelowTier1 + amountOnTier1Floor + amountAboveTier2);
        dnm.mint(user, amountBelowTier1 + amountOnTier1Floor + amountAboveTier2);

        // Case 1: below tier1 -> tier0
        vm.startPrank(user);
        dnm.approve(address(vault), amountBelowTier1);
        vault.redeem(amountBelowTier1);
        vm.stopPrank();
        uint256 expectedFee1 = (amountBelowTier1 * 1) / 100;
        assertEq(dai.balanceOf(feeReceiver), expectedFee1);

        // Case 2: exactly on tier1 floor -> tier1
        vm.startPrank(user);
        dnm.approve(address(vault), amountOnTier1Floor);
        vault.redeem(amountOnTier1Floor);
        vm.stopPrank();
        uint256 expectedFee2 = (amountOnTier1Floor * 2) / 100;
        assertEq(dai.balanceOf(feeReceiver), expectedFee1 + expectedFee2);

        // Case 3: above tier2 floor -> tier2
        vm.startPrank(user);
        dnm.approve(address(vault), amountAboveTier2);
        vault.redeem(amountAboveTier2);
        vm.stopPrank();
        uint256 expectedFee3 = (amountAboveTier2 * 3) / 100;
        assertEq(dai.balanceOf(feeReceiver), expectedFee1 + expectedFee2 + expectedFee3);
    }

    function testUpdateFeeTierAccessControl() public {
        vm.prank(user);
        vm.expectRevert();
        vault.updateFeeTier(0, 500, 100e18);
    }

    function testRemoveFeeTier() public {
        // Add 2 tiers
        vm.prank(admin1);
        vault.addFeeTier(100, 0);
        vm.prank(admin1);
        vault.addFeeTier(200, 500e18);

        // Remove tier 0
        vm.prank(admin1);
        vault.removeFeeTier(0);

        // Only 1 tier left
        (uint256 volumeFloor, uint16 feeBps) = vault.feeTiers(0);
        assertEq(feeBps, 200); // last tier moved to index 0
    }
}
