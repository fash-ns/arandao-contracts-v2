// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

contract SecurityGuard {
  error UnauthorizedContract(address contractAddress);
  error UnauthorizedAddress(address _address);

  /// @dev The timestamp of the contract deployment.
  uint256 deploymentTs;
  address owner;

  mapping(address => bool) orderCreatorContracts;
  mapping(address => bool) managers;

  constructor() {
    managers[msg.sender] = true;
    deploymentTs = block.timestamp;
    owner = msg.sender;
  }

  modifier onlyOrderCreatorContracts(address contractAddr) {
    if (!orderCreatorContracts[contractAddr]) {
      revert UnauthorizedContract(contractAddr);
    }
    _;
  }

  modifier onlyManager {
    if (!managers[msg.sender]) {
      revert UnauthorizedAddress(msg.sender);
    }
    _;
  }

  modifier onlyMigrateOperator() {
    require(
      deploymentTs + 30 days > block.timestamp,
      "The time for migration has been passed."
    );
    require(managers[msg.sender], "Sender address is not eligible to migrate.");
    _;
  }

  function addManager(address _addr) public onlyManager {
    managers[_addr] = true;
  }

  function revokeManager(address _addr) public onlyManager {
    require(_addr != msg.sender, "User cannot revoke itself");
    managers[_addr] = false;
  }

  function addWhiteListedContract(
    address _addr
  ) public onlyManager {
    orderCreatorContracts[_addr] = true;
  }

  function revokeWhiteListedContract(
    address _addr
  ) public onlyManager {
    orderCreatorContracts[_addr] = false;
  }

  function isOrderCreatorContract(address _addr) public view returns (bool) {
    return orderCreatorContracts[_addr];
  }

  function isManager(address _addr) public view returns (bool) {
    return managers[_addr];
  }
}
