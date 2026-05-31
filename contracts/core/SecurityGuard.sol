// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

import {SecurityGuardLib} from "./SecurityGuardLib.sol";

contract SecurityGuard is Ownable {
  error UnauthorizedContract(address contractAddress);
  error UnauthorizedAddress(address _address);

  /// @dev The timestamp of the contract deployment.
  address deployer;
  bool ownershipFlag;
  bool devMode;

  mapping(address => bool) orderCreatorContracts;
  mapping(address => bool) managers;

  constructor(address _owner, address _deployer) Ownable(_owner) {
    managers[_owner] = true;
    deployer = _deployer;
  }

  /**
   * @dev Override transferOwnership to allow only one transfer.
   */
  function transferOwnership(address newOwner) public override onlyOwner {
    if (ownershipFlag == false) {
      managers[owner()] = false;
      managers[newOwner] = true;
      super.transferOwnership(newOwner);
      ownershipFlag = true;
    } else {
      revert("Ownership has already been transferred");
    }
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

  modifier onlyDevMode() {
    require(devMode, "Developer mode is turned off");
    require(
      deployer == msg.sender,
      "Only deployer is valid to operate in dev mode."
    );
    _;
  }

  function _addManager(address _addr) internal {
    managers[_addr] = true;
    emit SecurityGuardLib.ManagerAdded(_addr);
  }

  function _revokeManager(address _addr) internal {
    require(_addr != msg.sender, "User cannot revoke itself");
    require(_addr != owner(), "User cannot revoke the owner of the contract");
    managers[_addr] = false;
    emit SecurityGuardLib.ManagerRevoked(_addr);
  }

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
