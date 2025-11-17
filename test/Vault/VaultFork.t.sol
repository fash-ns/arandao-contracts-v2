// // SPDX-License-Identifier: MIT
// pragma solidity ^0.8.27;

// import {Test} from "forge-std/Test.sol";
// import {MockToken} from "../mocks/MockToken.sol";
// import {MultiAssetVault} from "../../src/Vault/Vault.sol";
// import {VaultStorage} from "../../src/Vault/VaultCore/VaultStorage.sol";
// import {PriceFeed} from "../../src/Vault/VaultCore/PriceFeed.sol";
// import {MockV3Aggregator} from "../mocks/MockAggregator.sol";

// contract MultiAssetVaultRedeemTest is Test {
//     MockToken internal dai;
//     MockToken internal paxg;
//     MockToken internal wbtc;
//     MockToken internal dnm;
//     MultiAssetVault internal vault;

//     address internal user = address(1);
//     address internal admin1 = address(2);
//     address internal feeReceiver = address(3);

//     struct RedeemState {
//         uint256 userDai;
//         uint256 userPaxg;
//         uint256 userWbtc;
//         uint256 userArc;
//         uint256 feeDai;
//         uint256 feePaxg;
//         uint256 feeWbtc;
//         uint256 vaultDai;
//         uint256 vaultPaxg;
//         uint256 vaultWbtc;
//     }

//     struct ExpectedRedemption {
//         uint256 expectedUserDai;
//         uint256 expectedUserPaxg;
//         uint256 expectedUserWbtc;
//         uint256 daiFee;
//         uint256 paxgFee;
//         uint256 wbtcFee;
//     }

//     function setUp() public {
//         dai = new MockToken(address(this), 1_000_000e18);
//         paxg = new MockToken(address(this), 10_000e18);
//         wbtc = new MockToken(address(this), 1_000e18);
//         dnm = new MockToken(address(this), 0);

//         // Chainlink mock feeds
//         MockV3Aggregator paxgUsdFeed = new MockV3Aggregator(8, 3000e8);
//         MockV3Aggregator wbtcUsdFeed = new MockV3Aggregator(8, 100_000e8);
//         MockV3Aggregator daiUsdFeed = new MockV3Aggregator(8, 1e8);
//         PriceFeed feed = new PriceFeed(address(paxgUsdFeed), address(wbtcUsdFeed), address(daiUsdFeed), 8);

//         // Deploy vault
//         vault = new MultiAssetVault(
//             VaultStorage.InitParams({
//                 dai: address(dai),
//                 paxg: address(paxg),
//                 wbtc: address(wbtc),
//                 usdc: address(dai), // dummy
//                 arc: address(dnm),
//                 priceFeed: address(feed),
//                 coreContract: admin1,
//                 uniswapRouter: address(0),
//                 uniswapQuoter: address(0),
//                 initalOwner: admin1,
//                 feeReceiver: feeReceiver
//             })
//         );
//     }

//     /// @notice Test redeeming ARC and receiving base tokens, computing expected values on-chain
//     function testRedeemWithBaseTokens() public {
//         // 1) Setup vault balances
//         dai.mint(address(vault), 10_000e18);
//         paxg.mint(address(vault), 100e18);   // 1 PAXG = 3000 DAI
//         wbtc.mint(address(vault), 10e18);    // 1 WBTC = 100,000 DAI

//         // 2) ARC supply
//         uint256 userRedeemShares = 1_000e18;
//         uint256 totalSupply = 111_000e18;
//         dnm.mint(user, userRedeemShares);
//         dnm.mint(admin1, totalSupply - userRedeemShares);

//         // 3) Record pre-state
//         RedeemState memory before;
//         before.userDai = dai.balanceOf(user);
//         before.userPaxg = paxg.balanceOf(user);
//         before.userWbtc = wbtc.balanceOf(user);
//         before.userArc = dnm.balanceOf(user);
//         before.feeDai = dai.balanceOf(feeReceiver);
//         before.feePaxg = paxg.balanceOf(feeReceiver);
//         before.feeWbtc = wbtc.balanceOf(feeReceiver);
//         before.vaultDai = dai.balanceOf(address(vault));
//         before.vaultPaxg = paxg.balanceOf(address(vault));
//         before.vaultWbtc = wbtc.balanceOf(address(vault));

//         // 4) Approve and redeem
//         vm.startPrank(user);
//         dnm.approve(address(vault), userRedeemShares);
//         vault.redeemWithBaseTokens(userRedeemShares);
//         vm.stopPrank();

//         // 5) Compute expected redemption
//         uint256 bpsDenom = vault.BPS_DENOMINATOR();
//         uint16 feeBps = 0;

//         // Determine fee tier based on total DAI-equivalent payout
//         uint256 arcPrice = vault.getPrice();
//         uint256 totalDaiPayout = (arcPrice * userRedeemShares) / 1e18;

//         uint256 tiersCount = 6; // hardcoded tiers
//         for (uint256 i = 0; i < tiersCount; i++) {
//             (uint256 floor, uint16 bps) = vault.feeTiers(i);
//             if (totalDaiPayout >= floor) feeBps = bps;
//         }

//         // Compute pro-rata share of vault assets
//         uint256 daiProRata = (before.vaultDai * userRedeemShares) / totalSupply;
//         uint256 paxgProRata = (before.vaultPaxg * userRedeemShares) / totalSupply;
//         uint256 wbtcProRata = (before.vaultWbtc * userRedeemShares) / totalSupply;

//         // Compute fees
//         uint256 daiFee = (daiProRata * feeBps) / bpsDenom;
//         uint256 paxgFee = (paxgProRata * feeBps) / bpsDenom;
//         uint256 wbtcFee = (wbtcProRata * feeBps) / bpsDenom;

//         // Expected net to user
//         uint256 expectedUserDai = daiProRata - daiFee;
//         uint256 expectedUserPaxg = paxgProRata - paxgFee;
//         uint256 expectedUserWbtc = wbtcProRata - wbtcFee;

//         // 6) Assertions
//         assertEq(dnm.balanceOf(user), before.userArc - userRedeemShares, "ARC not burned");
//         assertEq(dai.balanceOf(user) - before.userDai, expectedUserDai, "User DAI incorrect");
//         assertEq(paxg.balanceOf(user) - before.userPaxg, expectedUserPaxg, "User PAXG incorrect");
//         assertEq(wbtc.balanceOf(user) - before.userWbtc, expectedUserWbtc, "User WBTC incorrect");

//         assertEq(dai.balanceOf(feeReceiver) - before.feeDai, daiFee, "FeeReceiver DAI incorrect");
//         assertEq(paxg.balanceOf(feeReceiver) - before.feePaxg, paxgFee, "FeeReceiver PAXG incorrect");
//         assertEq(wbtc.balanceOf(feeReceiver) - before.feeWbtc, wbtcFee, "FeeReceiver WBTC incorrect");

//         assertEq(dai.balanceOf(address(vault)), before.vaultDai - (expectedUserDai + daiFee), "Vault DAI mismatch");
//         assertEq(paxg.balanceOf(address(vault)), before.vaultPaxg - (expectedUserPaxg + paxgFee), "Vault PAXG mismatch");
//         assertEq(wbtc.balanceOf(address(vault)), before.vaultWbtc - (expectedUserWbtc + wbtcFee), "Vault WBTC mismatch");
//     }
// }
