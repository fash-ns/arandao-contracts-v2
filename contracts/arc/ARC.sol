// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

/**
 * @title AssetRightsCoin
 * @author Developer: Farbod Shams<farbodshams.2000@gmail.com>
 * website: https://dnm.pro
 */

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {ERC20Burnable} from "@openzeppelin/contracts/token/ERC20/extensions/ERC20Burnable.sol";

contract AssetRightsCoin is ERC20, ERC20Burnable {
  address public mintOperator;
  address public deployer;

  event DeployerRevoked();
  event MintOperatorSet(address operator);

  constructor() ERC20("AssetRightsCoin", "ARC") {
    deployer = msg.sender;
  }

  modifier onlyDeployer() {
    if (msg.sender != deployer) {
      revert("Only deployer can call");
    }
    _;
  }

  modifier onlyMintOperator() {
    require(mintOperator == msg.sender, "Only mint operator can mint");
    _;
  }

  function revokeDeployer() public onlyDeployer {
    deployer = address(0);
    emit DeployerRevoked();
  }

  function setMintOperator(address _operator) public onlyDeployer {
    require(mintOperator == address(0), "Mint operator is allready set.");
    mintOperator = _operator;
    emit MintOperatorSet(_operator);
  }

  function mint(address to, uint256 amount) public onlyMintOperator {
    _mint(to, amount);
  }
}
