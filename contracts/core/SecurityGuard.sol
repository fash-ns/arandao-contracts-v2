// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import {SecurityGuardLib} from "./SecurityGuardLib.sol";

contract SecurityGuard {
  error UnauthorizedContract(address contractAddress);
  error UnauthorizedAddress(address _address);

  /// @dev The timestamp of the contract deployment.
  uint256 deploymentTs;
  address securityGuardOwner;

  mapping(address => bool) orderCreatorContracts;
  mapping(address => bool) managers;

  constructor(address _owner) {
    managers[_owner] = true;
    deploymentTs = block.timestamp;
    securityGuardOwner = _owner;
  }

  function _securityGuardTransferOwnership(address newOwner) internal {
    managers[securityGuardOwner] = false;
    managers[newOwner] = true;
    securityGuardOwner = newOwner;
  }

  modifier onlyOrderCreatorContracts(address contractAddr) {
    if (!orderCreatorContracts[contractAddr]) {
      revert UnauthorizedContract(contractAddr);
    }
    _;
  }

  modifier onlyManager() {
    if (!managers[msg.sender]) {
      revert UnauthorizedAddress(msg.sender);
    }
    _;
  }

  function _addManager(address _addr) internal {
    managers[_addr] = true;
    emit SecurityGuardLib.ManagerAdded(_addr);
  }

  function _revokeManager(address _addr) internal {
    require(_addr != msg.sender, "User cannot revoke itself");
    require(
      _addr != securityGuardOwner,
      "User cannot revoke the owner of the contract"
    );
    managers[_addr] = false;
    emit SecurityGuardLib.ManagerRevoked(_addr);
  }

  //TODO: Implement revoke manager for owner.

  function _addWhiteListedContract(address _addr) internal {
    orderCreatorContracts[_addr] = true;
    emit SecurityGuardLib.WhiteListContractAdded(_addr);
  }

  function isOrderCreatorContract(address _addr) public view returns (bool) {
    return orderCreatorContracts[_addr];
  }

  function isManager(address _addr) public view returns (bool) {
    return managers[_addr];
  }
}
