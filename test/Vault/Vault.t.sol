// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import {Test} from "forge-std/Test.sol";
import {MultiAssetVault} from "../../src/Vault/Vault.sol";
import {VaultStorage} from "../../src/Vault/VaultCore/VaultStorage.sol";
import {PriceFeed} from "../../src/Vault/VaultCore/PriceFeed.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {MockToken} from "../mocks/MockToken.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";

contract MultiAssetVaultForkTest is Test {
    MultiAssetVault public vault;
    PriceFeed public feed;

    IERC20 public dai;
    IERC20 public paxg;
    IERC20 public wbtc;
    IERC20 public arc;

    address public owner;
    address public user;
    address public feeReceiver;
    address public coreContract;

    function setUp() public {
        // Fork mainnet
        vm.createSelectFork(
            "https://rpc.ankr.com/polygon/cea6f21cc6dc0df6ac58a42690aa0581b0e1981309f47385e0257994874b121e"
        );

        owner = address(this);
        user = address(0xABCD);
        feeReceiver = address(0xFEE);
        coreContract = makeAddr("core");

        // Real Chainlink feeds (mainnet)
        address paxgUsdFeed = 0x0f6914d8e7e1214CDb3A4C6fbf729b75C69DF608;
        address wbtcUsdFeed = 0xDE31F8bFBD8c84b5360CFACCa3539B938dd78ae6;
        address daiUsdFeed = 0x4746DeC9e833A82EC7C2C1356372CcF2cfcD2F3D;

        feed = new PriceFeed(paxgUsdFeed, wbtcUsdFeed, daiUsdFeed, 8);

        // Use mainnet tokens or mocks
        dai = IERC20(0x8f3Cf7ad23Cd3CaDbD9735AFf958023239c6A063);
        paxg = IERC20(0x553d3D295e0f695B9228246232eDF400ed3560B5);
        wbtc = IERC20(0x1BFD67037B42Cf73acF2047067bd4F2C47D9BfD6);
        arc = new MockToken(address(this), 1e20);

        // Init params struct
        VaultStorage.InitParams memory params = VaultStorage.InitParams({
            dai: address(dai),
            paxg: address(paxg),
            wbtc: address(wbtc),
            usdc: address(0x2791Bca1f2de4661ED88A30C99A7a9449Aa84174),
            arc: address(arc),
            priceFeed: address(feed),
            coreContract: coreContract,
            uniswapRouter: address(0xE592427A0AEce92De3Edee1F18E0157C05861564),
            uniswapQuoter: address(0xb27308f9F90D607463bb33eA1BeBb41C27CE5AB6),
            initialOwner: owner, // fixed typo
            feeReceiver: feeReceiver
        });

        // --- Deploy upgradeable vault ---
        MultiAssetVault impl = new MultiAssetVault();
        ERC1967Proxy proxy = new ERC1967Proxy(address(impl), abi.encodeCall(MultiAssetVault.initialize, (params)));
        vault = MultiAssetVault(address(proxy));

        // Fund the user with DAI on fork
        deal(address(dai), user, 1_000_000e18); // 1M DAI
        vm.deal(user, 100 ether); // native ETH for swaps
    }

    function testDepositAndGetPrice() public {
        uint256 depositAmount = 1000e18;

        vm.startPrank(user);
        dai.approve(address(vault), depositAmount);
        vault.deposit(depositAmount);

        uint256 price = vault.getPrice();
        emit log_named_uint("ARC price after deposit", price);

        uint256 daiBalance = dai.balanceOf(address(vault));
        emit log_named_uint("Vault DAI balance after deposit", daiBalance);

        uint256 wbtcBalance = wbtc.balanceOf(address(vault));
        emit log_named_uint("Vault WBTC balance after deposit", wbtcBalance);

        uint256 paxgBalance = paxg.balanceOf(address(vault));
        emit log_named_uint("Vault PAXG balance after deposit", paxgBalance);

        // Check price is reasonable (1e18 initial deposit)
        assertGt(price, 0);
        vm.stopPrank();
    }

    // function testRedeemARC() public {
    //     uint256 depositAmount = 1000e18;

    //     vm.startPrank(user);
    //     dai.approve(address(vault), depositAmount);
    //     vault.deposit(depositAmount);

    //     uint256 arcBalance = arc.balanceOf(user);
    //     emit log_named_uint("User ARC balance after deposit", arcBalance);

    //     // Redeem half
    //     uint256 redeemAmount = arcBalance / 2;
    //     vault.redeem(redeemAmount);

    //     uint256 daiBalanceAfter = dai.balanceOf(user);
    //     emit log_named_uint("User DAI after redeem", daiBalanceAfter);

    //     assertGt(daiBalanceAfter, 0);
    //     vm.stopPrank();
    // }

    // function testGetPriceWithZeroSupply() public {
    //     uint256 price = vault.getPrice();
    //     emit log_named_uint("ARC price with zero supply", price);

    //     assertEq(price, 1e18); // initial price when no ARC minted
    // }
}
