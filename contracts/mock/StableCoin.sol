// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

contract AranDAOStableCoin is ERC20, Ownable {
  constructor(
    address recipient,
    uint256 initialSupply
  ) ERC20("AranDAOStableCoin", "ASC") Ownable(msg.sender) {
    _mint(recipient, initialSupply * 10 ** decimals());
  }

  function mint(address to, uint256 amount) public onlyOwner {
    _mint(to, amount);
  }
}
