// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

contract UVM is ERC20, Ownable {
    constructor(
        string memory name,
        string memory symbol,
        uint initialSupply
    ) Ownable(msg.sender) ERC20(name, symbol) {
        require(
            initialSupply > 0,
            "Initial supply has to be greater than zero"
        );
        _mint(msg.sender, initialSupply * 10 ** 18);
    }

    function mint(address to, uint256 amount) public onlyOwner {
        _mint(to, amount);
    }
}
