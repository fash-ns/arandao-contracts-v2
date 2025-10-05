// // SPDX-License-Identifier: MIT
// pragma solidity ^0.8.27;

// import {Test} from "forge-std/Test.sol";
// import {MockToken} from "../mocks/MockToken.sol";
// import {MultiAssetVault} from "../../src/Vault/Vault.sol";
// import {PriceFeed} from "../../src/Vault/VaultCore/PriceFeed.sol";
// import {MockV3Aggregator} from "../mocks/MockAggregator.sol";
// import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
// import {MockRouter} from "../mocks/MockRouter.sol";

// contract MultiAssetVaultTest is Test {
//     MockToken internal paxg;
//     MockToken internal dai;
//     MockToken internal wbtc;
//     MockToken internal usdc;
//     MockToken internal dnm;

//     MockV3Aggregator internal paxgUsdFeed;
//     MockV3Aggregator internal wbtcUsdFeed;
//     MockV3Aggregator internal daiUsdFeed;

//     MultiAssetVault internal vault;
//     PriceFeed internal feed;
//     MockRouter internal mockRouter;

//     address internal owner = makeAddr("owner");
//     address internal user = makeAddr("user");
//     address internal admin1 = makeAddr("admin1");
//     address internal admin2 = makeAddr("admin2");
//     address internal admin3 = makeAddr("admin3");
//     address internal coreContract = makeAddr("core");
//     address internal feeReceiver = makeAddr("feeReceiver");

//     /// --------------------
//     /// Setup
//     /// --------------------
//     function setUp() public {
//         vm.startPrank(owner);

//         // Deploy tokens
//         paxg = new MockToken(user, 1e25);
//         dai = new MockToken(user, 1e25);
//         wbtc = new MockToken(user, 1e25);
//         usdc = new MockToken(user, 1e25);
//         dnm = new MockToken(address(this), 0);

//         // Chainlink mocks
//         paxgUsdFeed = new MockV3Aggregator(8, 3000e8);
//         wbtcUsdFeed = new MockV3Aggregator(8, 100000e8);
//         daiUsdFeed = new MockV3Aggregator(8, 1e8);

//         // PriceFeed
//         feed = new PriceFeed(address(paxgUsdFeed), address(wbtcUsdFeed), address(daiUsdFeed), 8);

//         // Router
//         mockRouter = new MockRouter();

//         // Vault
//         vault = new MultiAssetVault(
//             address(dai),
//             address(paxg),
//             address(wbtc),
//             address(usdc),
//             address(dnm),
//             address(feed),
//             coreContract,
//             address(mockRouter),
//             admin1,
//             admin2,
//             admin3,
//             feeReceiver
//         );

//         vm.stopPrank();
//     }

//     /// --------------------
//     /// PriceFeed Tests
//     /// --------------------
//     function testPriceFeedPaxgAndWbtc() public view {
//         uint256 paxgInDai = feed.getPaxgInDai();
//         uint256 expectedPaxg = 3000 * 1e18;
//         assertEq(paxgInDai, expectedPaxg);

//         uint256 wbtcInDai = feed.getWbtcInDai();
//         uint256 expectedWbtc = 100000 * 1e18;
//         assertEq(wbtcInDai, expectedWbtc);
//     }

//     /// --------------------
//     /// Vault Logic Tests
//     /// --------------------
//     function testVaultGetPriceWhenNoDnmSupply() public view {
//         uint256 price = vault.getPrice();
//         assertEq(price, 1e18);
//     }

//     function testEmergencyWithdrawRestrictedThenAllowed() public {
//         vm.prank(admin1);
//         vm.expectRevert(bytes("Emergency withdrawal restricted during grace period"));
//         vault.emergencyWithdraw();

//         vm.warp(block.timestamp + 91 days);
//         vm.prank(admin1);
//         vault.emergencyWithdraw(); // should not revert
//     }

//     function testWithrawDaiByCoreWhenSufficientBalance() public {
//         uint256 amount = 1e18;

//         vm.startPrank(user);
//         dai.transfer(address(vault), amount);
//         vm.stopPrank();

//         uint256 vaultDaiBefore = dai.balanceOf(address(vault));
//         assertEq(vaultDaiBefore, amount);

//         vm.prank(coreContract);
//         vault.withrawDai(amount);

//         assertEq(dai.balanceOf(address(vault)), 0);
//         assertEq(dai.balanceOf(coreContract), amount);
//     }

//     /// --------------------
//     /// Deposit / Redeem Tests
//     /// --------------------
//     function testDepositSplitsIntoAssets() public {
//         uint256 depositAmount = 1000e18;

//         vm.startPrank(user);
//         dai.approve(address(vault), depositAmount);
//         vault.deposit(depositAmount);
//         vm.stopPrank();

//         assertEq(dai.balanceOf(address(vault)), (depositAmount * 40) / 100);
//         assertEq(paxg.balanceOf(address(vault)), (depositAmount * 30) / 100);
//         assertEq(wbtc.balanceOf(address(vault)), (depositAmount * 30) / 100);
//     }

//     function testRedeemTransfersDAIAndFee() public {
//         uint256 lastUserBalance = dai.balanceOf(user);
//         uint256 depositAmount = 1000e18;

//         // Step 0: Make sure the vault has DAI
//         dai.mint(address(vault), depositAmount);

//         // Step 1: Mint DNM for the user to simulate supply
//         dnm.mint(user, depositAmount);
//         assertEq(dnm.totalSupply(), depositAmount); // sanity check

//         // Step 2: User approves and redeems DNM
//         vm.startPrank(user);
//         dnm.approve(address(vault), depositAmount);
//         vault.redeem(depositAmount);
//         vm.stopPrank();

//         // Step 3: Calculate expected net payout and fee
//         uint256 expectedNet = (depositAmount * 97) / 100; // 97% goes to user
//         uint256 expectedFee = (depositAmount * 3) / 100; // 3% fee

//         // Step 4: Assert balances
//         assertEq(dai.balanceOf(user) - lastUserBalance, expectedNet);
//         assertEq(dai.balanceOf(feeReceiver), expectedFee);
//     }
// }
