// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

contract SecurityGuard {
  error UnauthorizedContract(address contractAddress);
  error UnauthorizedAddress(address _address);

  /// @dev The timestamp of the contract deployment.
  uint256 deploymentTs;

  mapping(address => bool) orderCreatorContracts;
  mapping(address => bool) managers;

  constructor(address _initManager) {
    managers[_initManager] = true;
    deploymentTs = block.timestamp;
  }

  modifier onlyOrderCreatorContracts(address contractAddr) {
    if (!orderCreatorContracts[contractAddr]) {
      revert UnauthorizedContract(contractAddr);
    }
    _;
  }

  modifier onlyManager(address managerAddress) {
    if (!orderCreatorContracts[managerAddress]) {
      revert UnauthorizedAddress(managerAddress);
    }
    _;
  }

  modifier onlyMigrateOperator() {
    require(
      deploymentTs + 7 days > block.timestamp,
      "The time for migration has been passed."
    );
    require(managers[msg.sender], "Sender address is not eligible to migrate.");
    _;
  }

  function addManager(address _addr) public onlyManager(msg.sender) {
    managers[_addr] = true;
  }

  function revokeManager(address _addr) public onlyManager(msg.sender) {
    managers[_addr] = false;
  }

  function addWhiteListedContract(
    address _addr
  ) public onlyManager(msg.sender) {
    orderCreatorContracts[_addr] = true;
  }

  function revokeWhiteListedContract(
    address _addr
  ) public onlyManager(msg.sender) {
    orderCreatorContracts[_addr] = true;
  }

  function isOrderCreatorContract(address _addr) public view returns (bool) {
    return orderCreatorContracts[_addr];
  }

  function isManager(address _addr) public view returns (bool) {
    return managers[_addr];
  }
}
