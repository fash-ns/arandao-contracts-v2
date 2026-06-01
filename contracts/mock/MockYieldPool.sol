// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

contract MockYieldPool {
  address paymentToken;

  constructor(address _paymentToken) {
    paymentToken = _paymentToken;
  }

  function notifyReward(uint256 amount) public {
    IERC20 usdt = IERC20(paymentToken);
    usdt.transferFrom(msg.sender, address(this), amount);
  }
}
