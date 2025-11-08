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
  bool ownershipTransferredFlag;
  uint256 deploymentTs;
  uint256 public limitedRemainingMintCap;
  address mintOperator;

  constructor(
    address recipient,
    uint256 initialSupply
  ) ERC20("AssetRightsCoin", "ARC") Ownable(msg.sender) {
    deploymentTs = block.timestamp;
    limitedRemainingMintCap = 900 ether;
    _mint(recipient, initialSupply * 10 ** decimals());
  }

  function limitedMint(uint256 amount) public onlyOwner {
    require(
      block.timestamp < deploymentTs + 270 days,
      "Limited mint time is over."
    );
    require(
      amount <= limitedRemainingMintCap,
      "Insufficient remaining mint cap."
    );
    limitedRemainingMintCap -= amount;
    _mint(msg.sender, amount);
  }

  function setMintOperator(address _operator) public onlyOwner {
    mintOperator = _operator;
  }

  modifier onlyMintOperator() {
    require(mintOperator == msg.sender, "Only mint operator can mint");
    _;
  }

  function mint(address to, uint256 amount) public onlyMintOperator {
    _mint(to, amount);
  }

  /**
   * @dev Override transferOwnership to allow only one transfer.
   */
  function transferOwnership(address newOwner) public override onlyOwner {
    if (ownershipTransferredFlag == false) {
      super.transferOwnership(newOwner);
      ownershipTransferredFlag = true;
    } else {
      revert("Ownership has already been transferred");
    }
  }
}
