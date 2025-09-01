//SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

/**
 * @title erc20 mock Token
 */
contract MockToken is ERC20 {
    constructor(address to, uint256 amount) ERC20("MockToken", "MTKn") {
        _mint(to, amount);
    }

    function mint(address to, uint256 amount) external {
        _mint(to, amount);
    }
}
