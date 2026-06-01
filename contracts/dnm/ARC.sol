// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

/**
 * @title AssetRightsCoin
 * @author Developer: Farbod Shams<farbodshams.2000@gmail.com>
 * website: https://dnm.pro
 */

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {ERC20Burnable} from "@openzeppelin/contracts/token/ERC20/extensions/ERC20Burnable.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

contract AssetRightsCoin is ERC20, ERC20Burnable, Ownable {
  address public mintOperator;
  address public deployer;

  constructor(
    address _initialOwner
  ) ERC20("AssetRightsCoin", "ARC") Ownable(_initialOwner) {
    deployer = msg.sender;
  }

  modifier onlyDeployer() {
    if (msg.sender != owner() && msg.sender != deployer) {
      revert("Only owner or deployer can call");
    }
    _;
  }

  modifier onlyMintOperator() {
    require(mintOperator == msg.sender, "Only mint operator can mint");
    _;
  }

  function revokeDeployer() public onlyDeployer {
    deployer = address(0);
  }

  function setMintOperator(address _operator) public onlyDeployer {
    require(mintOperator == address(0), "Mint operator is allready set.");
    mintOperator = _operator;
  }

  function mint(address to, uint256 amount) public onlyMintOperator {
    _mint(to, amount);
  }
}
