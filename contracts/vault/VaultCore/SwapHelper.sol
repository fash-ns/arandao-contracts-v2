// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {VaultStorage} from "./VaultStorage.sol";
import {ISwapRouter} from "@uniswap/v3-periphery/contracts/interfaces/ISwapRouter.sol";

/**
 * @title SwapHelper
 * @notice Swap helper that routes all swaps through USDC for liquidity consistency.
 * - All routes use USDC as intermediary.
 * - Handles multi-hop swaps for tokens without direct DAI pairs (e.g. WBTC).
 * - Uses SafeERC20.forceApprove for safe allowance management.
 */
abstract contract SwapHelper is VaultStorage {
  using SafeERC20 for IERC20;

  function _encodePath(
    address[] memory tokens,
    uint24[] memory fees
  ) internal pure returns (bytes memory path) {
    require(tokens.length >= 2, "Path: too few tokens");
    require(fees.length == tokens.length - 1, "Path: fees length mismatch");

    path = abi.encodePacked(tokens[0]);
    for (uint256 i = 0; i < fees.length; ++i) {
      path = abi.encodePacked(path, fees[i], tokens[i + 1]);
    }
  }

  /// @notice Swaps DAI into another token via USDC
  function _swapFromDai(
    address tokenOut,
    uint256 amountIn,
    address to
  ) internal {
    require(amountIn > 0, "AmountIn > 0");
    require(tokenOut != address(0), "Invalid tokenOut");

    uint256 deadline = block.timestamp + _deadlineDuration;
    IERC20(DAI).forceApprove(address(_uniswapRouter), amountIn);

    bytes memory path;
    uint256 expectedOut;

    if (tokenOut == USDC) {
      // DAI -> USDC (single-hop)
      address[] memory tokens = new address[](2);
      tokens[0] = DAI;
      tokens[1] = USDC;

      uint24[] memory fees = new uint24[](1);
      fees[0] = _feeUsdcDai;

      path = _encodePath(tokens, fees);
    } else {
      // DAI -> USDC -> tokenOut
      address[] memory tokens = new address[](3);
      tokens[0] = DAI;
      tokens[1] = USDC;
      tokens[2] = tokenOut;

      uint24[] memory fees = new uint24[](2);
      fees[0] = _feeUsdcDai;
      fees[1] = _getUsdcFeeForToken(tokenOut);

      path = _encodePath(tokens, fees);
    }

    expectedOut = _uniswapQuoter.quoteExactInput(path, amountIn);
    uint256 minOut = (expectedOut * (_slippageDenominator - _slippageBps)) /
      _slippageDenominator;

    ISwapRouter.ExactInputParams memory params = ISwapRouter.ExactInputParams({
      path: path,
      recipient: to,
      deadline: deadline,
      amountIn: amountIn,
      amountOutMinimum: minOut
    });

    _uniswapRouter.exactInput(params);
    IERC20(DAI).forceApprove(address(_uniswapRouter), 0);
  }

  /// @notice Swaps tokenIn into DAI via USDC
  function _swapToDai(address tokenIn, uint256 amountIn, address to) internal {
    require(tokenIn != DAI, "Already DAI");
    require(amountIn > 0, "AmountIn > 0");

    uint256 deadline = block.timestamp + _deadlineDuration;
    IERC20(tokenIn).forceApprove(address(_uniswapRouter), amountIn);

    bytes memory path;
    uint256 expectedOut;

    if (tokenIn == USDC) {
      // USDC -> DAI (single-hop)
      address[] memory tokens = new address[](2);
      tokens[0] = USDC;
      tokens[1] = DAI;

      uint24[] memory fees = new uint24[](1);
      fees[0] = _feeUsdcDai;

      path = _encodePath(tokens, fees);
    } else {
      // tokenIn -> USDC -> DAI
      address[] memory tokens = new address[](3);
      tokens[0] = tokenIn;
      tokens[1] = USDC;
      tokens[2] = DAI;

      uint24[] memory fees = new uint24[](2);
      fees[0] = _getUsdcFeeForToken(tokenIn);
      fees[1] = _feeUsdcDai;

      path = _encodePath(tokens, fees);
    }

    expectedOut = _uniswapQuoter.quoteExactInput(path, amountIn);
    uint256 minOut = (expectedOut * (_slippageDenominator - _slippageBps)) /
      _slippageDenominator;

    ISwapRouter.ExactInputParams memory params = ISwapRouter.ExactInputParams({
      path: path,
      recipient: to,
      deadline: deadline,
      amountIn: amountIn,
      amountOutMinimum: minOut
    });

    _uniswapRouter.exactInput(params);
    IERC20(tokenIn).forceApprove(address(_uniswapRouter), 0);
  }

  /// @notice Swaps tokenIn for exact DAI amount via USDC
  function _swapForExactDai(
    address tokenIn,
    uint256 amountOut,
    uint256 amountInMax,
    address to
  ) internal {
    require(tokenIn != DAI, "Already DAI");
    require(amountOut > 0, "AmountOut > 0");

    uint256 deadline = block.timestamp + _deadlineDuration;
    IERC20(tokenIn).forceApprove(address(_uniswapRouter), amountInMax);

    bytes memory path;

    address[] memory tokens = new address[](3);
    tokens[0] = DAI; // tokenOut (what we want exactly)
    tokens[1] = USDC; // intermediary
    tokens[2] = tokenIn; // token we will spend

    uint24[] memory fees = new uint24[](2);
    fees[0] = _feeUsdcDai; // fee for DAI <-> USDC
    fees[1] = _getUsdcFeeForToken(tokenIn); // fee for USDC <-> tokenIn

    path = _encodePath(tokens, fees);

    ISwapRouter.ExactOutputParams memory params = ISwapRouter
      .ExactOutputParams({
        path: path,
        recipient: to,
        deadline: deadline,
        amountOut: amountOut,
        amountInMaximum: amountInMax
      });

    _uniswapRouter.exactOutput(params);
    IERC20(tokenIn).forceApprove(address(_uniswapRouter), 0);
  }

  function _getUsdcFeeForToken(address token) internal view returns (uint24) {
    if (token == WBTC) return _feeUsdcWbtc;
    if (token == PAXG) return _feeUsdcPaxg;
    return _feeDefault;
  }
}
