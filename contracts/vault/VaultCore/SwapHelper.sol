// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {IUniswapV2Router02} from "@uniswap/v2-periphery/contracts/interfaces/IUniswapV2Router02.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {VaultStorage} from "./VaultStorage.sol";

/**
 * @title SwapHelper
 * @notice Provides secure, internal helper functions for swapping tokens via the Uniswap V2 Router,
 * managing allowances safely using OpenZeppelin's SafeERC20/forceApprove method.
 * @custom:dev-notes This contract is abstract and requires an inheriting contract to implement
 * the constructor and set the configured state variables.
 */
abstract contract SwapHelper is VaultStorage {
  using SafeERC20 for IERC20;

  /**
   * @notice Executes a swap from the base token (DAI) to a target token (tokenOut).
   * @param tokenOut The address of the token to receive.
   * @param amountIn The exact amount of DAI to sell.
   * @param to The address that will receive the resulting tokenOut.
   */
  function _swapFromDAI(
    address tokenOut,
    uint256 amountIn,
    address to
  ) internal {
    // Calculate deadline
    uint256 deadline = block.timestamp + _deadlineDuration;

    // Approve the router using forceApprove for secure allowance set
    IERC20(DAI).forceApprove(address(_uniswapRouter), amountIn);

    address[] memory path = new address[](2);
    path[0] = DAI;
    path[1] = tokenOut;

    // Get expected amount out from Uniswap to calculate slippage limit
    uint256[] memory amountsOut = _uniswapRouter.getAmountsOut(amountIn, path);
    uint256 expectedOut = amountsOut[amountsOut.length - 1];

    // Calculate minOut based on configured slippage
    uint256 minOut = (expectedOut * (_slippageDenominator - _slippageBps)) /
      _slippageDenominator;

    _uniswapRouter.swapExactTokensForTokensSupportingFeeOnTransferTokens(
      amountIn,
      minOut, // Using the calculated minOut
      path,
      to,
      deadline
    );

    // Reset allowance securely
    IERC20(DAI).forceApprove(address(_uniswapRouter), 0);
  }

  /**
   * @notice Executes a swap from a source token (tokenIn) to the base token (DAI), ensuring an exact amount of DAI is received.
   * @dev Uses Uniswap V2 Router's swapTokensForExactTokensSupportingFeeOnTransferTokens.
   * @param tokenIn The address of the token to sell.
   * @param amountOut The exact amount of DAI to receive.
   * @param amountInMax The maximum amount of tokenIn to spend.
   * @param to The address that will receive the resulting DAI tokens.
   */
  function _swapForExactDAI(
    address tokenIn,
    uint256 amountOut,
    uint256 amountInMax,
    address to
  ) internal {
    require(tokenIn != DAI, "Token is already DAI");
    require(amountOut > 0, "Amount out must be greater than zero");

    uint256 deadline = block.timestamp + _deadlineDuration;

    // Approve the router using forceApprove for secure allowance set (using amountInMax)
    IERC20(tokenIn).forceApprove(address(_uniswapRouter), amountInMax);

    // Build path: tokenIn -> DAI
    address[] memory path = new address[](2);
    path[0] = tokenIn;
    path[1] = DAI;

    // Perform swap
    // Note: swapTokensForExactTokens requires amountOut as the first argument
    _uniswapRouter.swapTokensForExactTokens(
      amountOut,
      amountInMax,
      path,
      to,
      deadline
    );

    // Reset allowance securely
    IERC20(tokenIn).forceApprove(address(_uniswapRouter), 0);
  }

  /**
   * @notice Executes a swap from a source token (tokenIn) to the base token (DAI).
   * @param tokenIn The address of the token to sell.
   * @param amountIn The exact amount of tokenIn to sell.
   * @param to The address that will receive the resulting DAI tokens.
   */
  function _swapToDAI(address tokenIn, uint256 amountIn, address to) internal {
    require(tokenIn != DAI, "Token is already DAI");
    require(amountIn > 0, "Amount must be greater than zero");

    uint256 deadline = block.timestamp + _deadlineDuration;

    // Approve the router using forceApprove for secure allowance set
    IERC20(tokenIn).forceApprove(address(_uniswapRouter), amountIn);

    // Build path: tokenIn -> DAI
    address[] memory path = new address[](2);
    path[0] = tokenIn;
    path[1] = DAI;

    // Get expected amount out from Uniswap to calculate slippage limit
    uint256[] memory amountsOut = _uniswapRouter.getAmountsOut(amountIn, path);
    uint256 expectedOut = amountsOut[amountsOut.length - 1];

    // Calculate minOut based on configured slippage
    uint256 minOut = (expectedOut * (_slippageDenominator - _slippageBps)) /
      _slippageDenominator;

    // Perform swap
    _uniswapRouter.swapExactTokensForTokensSupportingFeeOnTransferTokens(
      amountIn,
      minOut,
      path,
      to,
      deadline
    );

    // Reset allowance securely
    IERC20(tokenIn).forceApprove(address(_uniswapRouter), 0);
  }
}
