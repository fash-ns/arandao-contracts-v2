// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

library SecurityGuardLib {
    event ManagerAdded(address indexed managerAddr);
    event ManagerRevoked(address indexed managerAddr);

    event WhiteListContractAdded(address indexed contractAddr);
    event WhiteListContractRevoked(address indexed contractAddr);
}
