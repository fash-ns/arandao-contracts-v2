// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import "forge-std/Test.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {ISwapRouter} from "@uniswap/v3-periphery/contracts/interfaces/ISwapRouter.sol";
import {IQuoter} from "@uniswap/v3-periphery/contracts/interfaces/IQuoter.sol";
import {SwapHelper} from "../../src/Vault/VaultCore/SwapHelper.sol";
import {VaultStorage} from "../../src/Vault/VaultCore/VaultStorage.sol";

contract SwapHelperTest is Test {
    // --- Mainnet Addresses ---
    address constant DAI = 0x8f3Cf7ad23Cd3CaDbD9735AFf958023239c6A063;
    address constant USDC = 0x2791Bca1f2de4661ED88A30C99A7a9449Aa84174;
    address constant WBTC = 0x1BFD67037B42Cf73acF2047067bd4F2C47D9BfD6;
    address constant PAXG = 0x553d3D295e0f695B9228246232eDF400ed3560B5;

    ISwapRouter constant UNISWAP_ROUTER = ISwapRouter(0xE592427A0AEce92De3Edee1F18E0157C05861564);
    IQuoter constant UNISWAP_QUOTER = IQuoter(0xb27308f9F90D607463bb33eA1BeBb41C27CE5AB6);

    address testUser = makeAddr("user");

    SwapHelperWrapper swapHelper;

    function setUp() public {
        vm.createSelectFork("https://rpc.ankr.com/polygon/cea6f21cc6dc0df6ac58a42690aa0581b0e1981309f47385e0257994874b121e");
        swapHelper = new SwapHelperWrapper(DAI, PAXG, WBTC, USDC, address(0), address(0), address(this), address(UNISWAP_ROUTER), address(UNISWAP_QUOTER));

        // Fund testUser with DAI for testing
        deal(DAI, testUser, 10_000e18);
        deal(USDC, testUser, 10_000e6);
        deal(WBTC, testUser, 10e8); // 10 WBTC

        // Impersonate an account that already holds tokens (DAI whale)
        address daiWhale = 0x4bf61e01450574dC15229542A1EF785af3Dc1Bb3; 
        vm.startPrank(daiWhale);
        IERC20(DAI).transfer(testUser, 100000e18);
        vm.stopPrank();

        address usdcWhale = 0x1347378B1d0Eb69d3462e09b3dFa2Fe28ebE74eC;
        vm.startPrank(usdcWhale);
        IERC20(USDC).transfer(testUser, 100000e6);
        vm.stopPrank();

        // WBTC whale
        address wbtcWhale = 0x0AFF6665bB45bF349489B20E225A6c5D78E2280F;
        vm.startPrank(wbtcWhale);
        IERC20(WBTC).transfer(testUser, 10e8);
        vm.stopPrank();
    }

    function testSwapFromDAIToUSDC() public {
        uint256 amountIn = 100e18;
        vm.startPrank(testUser);

        IERC20(DAI).transfer(address(swapHelper), amountIn);
        swapHelper.swapFromDAI(USDC, amountIn, testUser);

        uint256 usdcBalance = IERC20(USDC).balanceOf(testUser);
        assertGt(usdcBalance, 0, "USDC balance should increase");
        vm.stopPrank();
    }

    function testSwapFromDAIToWBTC() public {
        uint256 amountIn = 100e18;
        vm.startPrank(testUser);

        IERC20(DAI).transfer(address(swapHelper), amountIn);
        swapHelper.swapFromDAI(WBTC, amountIn, testUser);

        uint256 wbtcBalance = IERC20(WBTC).balanceOf(testUser);
        assertGt(wbtcBalance, 0, "WBTC balance should increase");
        vm.stopPrank();
    }

    function testSwapToDAIFromUSDC() public {
        uint256 amountIn = 100e6;
        vm.startPrank(testUser);

        IERC20(USDC).transfer(address(swapHelper), amountIn);
        swapHelper.swapToDAI(USDC, amountIn, testUser);

        uint256 daiBalance = IERC20(DAI).balanceOf(testUser);
        assertGt(daiBalance, 0, "DAI balance should increase");
        vm.stopPrank();
    }

    function testSwapForExactDAIFromWBTC() public {
        uint256 amountOut = 50e18;
        uint256 amountInMax = 1e8; // 1 WBTC max

        vm.startPrank(testUser);

        IERC20(WBTC).transfer(address(swapHelper), amountInMax);

        uint256 lastBalance = IERC20(DAI).balanceOf(testUser);

        swapHelper.swapForExactDAI(WBTC, amountOut, amountInMax, testUser);

        uint256 newBalance = IERC20(DAI).balanceOf(testUser);
        assertEq(newBalance - lastBalance, amountOut, "DAI balance should match exact output");

        vm.stopPrank();
    }
}

// Simple wrapper contract inheriting SwapHelper for testing
contract SwapHelperWrapper is SwapHelper {
    constructor(
        address dai,
        address paxg,
        address wbtc,
        address usdc,
        address dnm,
        address priceFeed,
        address coreAddr,
        address uniswapRouter,
        address uniswapQuoter
    ) VaultStorage(
        VaultStorage.InitParams({
            dai: dai,
            paxg: paxg,
            wbtc: wbtc,
            usdc: usdc,
            dnm: dnm,
            priceFeed: priceFeed,
            coreContract: coreAddr,
            uniswapRouter: uniswapRouter,
            uniswapQuoter: uniswapQuoter,
            admin1: address(0),
            admin2: address(0),
            admin3: address(0),
            feeReceiver: address(0)
        })
    ) {
    }

    function swapFromDAI(address tokenOut, uint256 amountIn, address to) external {
        _swapFromDAI(tokenOut, amountIn, to);
    }

    function swapToDAI(address tokenIn, uint256 amountIn, address to) external {
        _swapToDAI(tokenIn, amountIn, to);
    }

    function swapForExactDAI(address tokenIn, uint256 amountOut, uint256 amountInMax, address to) external {
        _swapForExactDAI(tokenIn, amountOut, amountInMax, to);
    }
}