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

    function __SecurityGuard_init(address _owner) internal {
        managers[_owner] = true;
        deploymentTs = block.timestamp;
        securityGuardOwner = _owner;
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

    modifier onlyMigrateOperator() {
        require(
            deploymentTs + 90 days > block.timestamp,
            "The time for migration has been passed."
        );
        require(
            msg.sender == securityGuardOwner,
            "Sender address is not eligible to migrate."
        );
        _;
    }

    function addManager(address _addr) public onlyManager {
        managers[_addr] = true;
        emit SecurityGuardLib.ManagerAdded(_addr);
    }

    function revokeManager(address _addr) public onlyManager {
        require(_addr != msg.sender, "User cannot revoke itself");
        require(_addr != securityGuardOwner, "User cannot revoke the owner of the contract");
        managers[_addr] = false;
        emit SecurityGuardLib.ManagerRevoked(_addr);
    }

    function addWhiteListedContract(address _addr) public onlyManager {
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
