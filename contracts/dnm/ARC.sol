// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {ERC20Burnable} from "@openzeppelin/contracts/token/ERC20/extensions/ERC20Burnable.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

contract AssetRightsCoin is ERC20, ERC20Burnable, Ownable {
  mapping(address => bool) public isMintOperator;

  constructor(
    address recipient,
    uint256 initialSupply
  ) ERC20("AssetRightsCoin", "ARC") Ownable(msg.sender) {
    _mint(recipient, initialSupply * 10 ** decimals());
  }

  function setMintOperator(
    address _operator,
    bool _isMintOperator
  ) public onlyOwner {
    isMintOperator[_operator] = _isMintOperator;
  }

  modifier onlyMintOperator() {
    require(isMintOperator[msg.sender], "Only mint operator can mint");
    _;
  }

  function mint(address to, uint256 amount) public onlyMintOperator {
    _mint(to, amount);
  }
}
