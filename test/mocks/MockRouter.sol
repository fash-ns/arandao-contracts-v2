// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

contract MockRouter {
    // trivial 1:1 swap: take `amountIn` of path[0], mint same amount of path[1]
    function getAmountsOut(uint256 amountIn, address[] calldata) external pure returns (uint256[] memory) {
        uint256[] memory arr = new uint256[](2);
        arr[0] = amountIn;
        arr[1] = amountIn;
        return arr;
    }

    function swapExactTokensForTokensSupportingFeeOnTransferTokens(
        uint256 amountIn,
        uint256, // amountOutMin (ignored in mock)
        address[] calldata path,
        address to,
        uint256 // deadline (ignored)
    ) external {
        // pull tokenIn from caller (vault)
        IERC20(path[0]).transferFrom(msg.sender, address(this), amountIn);

        // mint tokenOut 1:1 to recipient
        IMintable(path[1]).mint(to, amountIn);
    }

    function swapTokensForExactTokens(
        uint256 amountOut,
        uint256 amountInMax,
        address[] calldata path,
        address to,
        uint256 // deadline
    ) external {
        // pull tokenIn max (mock consumes amountInMax)
        IERC20(path[0]).transferFrom(msg.sender, address(this), amountInMax);

        // mint exact amountOut to recipient
        IMintable(path[1]).mint(to, amountOut);
    }
}

interface IMintable {
    function mint(address to, uint256 amount) external;
}
