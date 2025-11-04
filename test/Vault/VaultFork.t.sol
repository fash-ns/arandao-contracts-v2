// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import "forge-std/Test.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {MultiAssetVault} from "../../src/Vault/Vault.sol";
import {VaultStorage} from "../../src/Vault/VaultCore/VaultStorage.sol";
import {MockToken} from "../mocks/MockToken.sol";

contract MultiAssetVaultForkSwapTest is Test {
    // --- Polygon Mainnet Tokens ---
    address constant DAI = 0x8f3Cf7ad23Cd3CaDbD9735AFf958023239c6A063;
    address constant USDC = 0x2791Bca1f2de4661ED88A30C99A7a9449Aa84174;
    address constant WBTC = 0x1BFD67037B42Cf73acF2047067bd4F2C47D9BfD6;
    address constant PAXG = 0x553d3D295e0f695B9228246232eDF400ed3560B5;

    // --- Uniswap Router + Quoter ---
    address constant UNISWAP_ROUTER = 0xE592427A0AEce92De3Edee1F18E0157C05861564;
    address constant UNISWAP_QUOTER = 0xb27308f9F90D607463bb33eA1BeBb41C27CE5AB6;

    // --- Test participants ---
    address internal user = makeAddr("user");
    address internal admin1 = makeAddr("admin1");
    address internal admin2 = makeAddr("admin2");
    address internal admin3 = makeAddr("admin3");
    address internal feeReceiver = makeAddr("feeReceiver");
    address internal coreContract = makeAddr("core");

    MultiAssetVault internal vault;
    MockToken internal dnm; // ARC substitute

    function setUp() public {
        // Polygon fork
        vm.createSelectFork(
            "https://rpc.ankr.com/polygon/cea6f21cc6dc0df6ac58a42690aa0581b0e1981309f47385e0257994874b121e"
        );

        // Deploy local DNM (ARC) mock token
        dnm = new MockToken(address(this), 0);

        // Initialize vault params with live assets
        VaultStorage.InitParams memory params = VaultStorage.InitParams({
            dai: DAI,
            paxg: PAXG,
            wbtc: WBTC,
            usdc: USDC,
            arc: address(dnm),
            priceFeed: address(0),
            coreContract: coreContract,
            uniswapRouter: UNISWAP_ROUTER,
            uniswapQuoter: UNISWAP_QUOTER,
            initalOwner: admin1,
            feeReceiver: feeReceiver
        });

        vault = new MultiAssetVault(params);

        // Enable swaps
        vm.prank(admin1);
        vault.updateSwapEnabled(true);

        // Fund the test user with real mainnet DAI
        address daiWhale = 0x7A81BBFe9516f81e49c163364264e53b71a49298;
        vm.startPrank(daiWhale);
        IERC20(DAI).transfer(user, 5_000e18);
        vm.stopPrank();

        vm.prank(admin1);
        vault.addFeeTier(100, 0);
        vm.prank(admin1);
        vault.addFeeTier(200, 500e18);
        vm.prank(admin1);
        vault.addFeeTier(300, 1000e18);
    }

    /// ----------------------------------------------------
    /// Test 1 — Deposit triggers real swaps via Vault
    /// ----------------------------------------------------
    function testDepositPerformsLiveSwaps() public {
        uint256 depositAmount = 1000e18;

        vm.startPrank(user);
        IERC20(DAI).approve(address(vault), depositAmount);

        uint256 daiBefore = IERC20(DAI).balanceOf(address(vault));
        uint256 paxgBefore = IERC20(PAXG).balanceOf(address(vault));
        uint256 wbtcBefore = IERC20(WBTC).balanceOf(address(vault));

        vault.deposit(depositAmount);

        vm.stopPrank();

        uint256 daiAfter = IERC20(DAI).balanceOf(address(vault));
        uint256 paxgAfter = IERC20(PAXG).balanceOf(address(vault));
        uint256 wbtcAfter = IERC20(WBTC).balanceOf(address(vault));

        // Verify swaps occurred
        assertGt(paxgAfter, paxgBefore, "Vault PAXG should increase");
        assertGt(wbtcAfter, wbtcBefore, "Vault WBTC should increase");
        assertGt(daiAfter, 0, "Vault should retain some DAI portion");
    }

    /// ----------------------------------------------------
    /// Test 2 — Redeem converts back to DAI
    /// ----------------------------------------------------
    function testRedeemPerformsLiveSwaps() public {
        uint256 depositAmount = 1500e18;

        // Deposit first (generates DNM)
        vm.startPrank(user);
        IERC20(DAI).approve(address(vault), depositAmount);
        vault.deposit(depositAmount);
        vm.stopPrank();

        // Mint mock DNM manually to simulate ownership
        dnm.mint(user, depositAmount);

        // Check user DAI before redeem
        uint256 daiBefore = IERC20(DAI).balanceOf(user);

        vm.startPrank(user);
        dnm.approve(address(vault), depositAmount);
        vault.redeem(depositAmount);
        vm.stopPrank();

        uint256 daiAfter = IERC20(DAI).balanceOf(user);
        assertGt(daiAfter, daiBefore, "User DAI balance should increase after redeem");
    }

    /// ----------------------------------------------------
    /// Test 3 — Zero deposit reverts
    /// ----------------------------------------------------
    function testZeroDepositReverts() public {
        vm.startPrank(user);
        vm.expectRevert(bytes("Deposit amount must be > 0"));
        vault.deposit(0);
        vm.stopPrank();
    }

    function testWithdrawDaiTriggersExactDaiSwaps() public {
        uint256 depositAmount = 2000e18;

        // Step 1: Deposit DAI to create PAXG/WBTC reserves
        vm.startPrank(user);
        IERC20(DAI).approve(address(vault), depositAmount);
        vault.deposit(depositAmount);
        vm.stopPrank();

        // Step 2: Record pre-withdrawal balances
        uint256 daiBeforeVault = IERC20(DAI).balanceOf(address(vault));
        uint256 paxgBefore = IERC20(PAXG).balanceOf(address(vault));
        uint256 wbtcBefore = IERC20(WBTC).balanceOf(address(vault));
        uint256 daiBeforeCore = IERC20(DAI).balanceOf(coreContract);

        // Step 3: Withdraw more DAI than vault holds to trigger swaps
        uint256 withdrawAmount = daiBeforeVault + 200e18;

        vm.startPrank(coreContract);
        vault.withdrawDai(withdrawAmount);
        vm.stopPrank();

        // Step 4: Record after-withdrawal balances
        uint256 daiAfterVault = IERC20(DAI).balanceOf(address(vault));
        uint256 paxgAfter = IERC20(PAXG).balanceOf(address(vault));
        uint256 wbtcAfter = IERC20(WBTC).balanceOf(address(vault));
        uint256 daiAfterCore = IERC20(DAI).balanceOf(coreContract);

        // Assertions
        // Vault DAI should decrease
        assertLt(daiAfterVault, daiBeforeVault, "Vault DAI decreased after withdrawal");

        // PAXG and WBTC should decrease (sold for DAI)
        assertLt(paxgAfter, paxgBefore, "Vault sold some PAXG");
        assertLt(wbtcAfter, wbtcBefore, "Vault sold some WBTC");

        // Core contract should receive DAI
        assertGt(daiAfterCore, daiBeforeCore, "Core contract received DAI");
    }
}
