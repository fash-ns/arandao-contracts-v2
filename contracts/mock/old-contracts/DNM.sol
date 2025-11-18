// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";

contract DNM is ERC20 {
    uint256 public MAX_SUPPLY = 10000000 ether;
    address public OWNER;

    constructor(string memory name, string memory symbol) ERC20(name, symbol) {
        OWNER = msg.sender;
    }

    function mintByOwner(address send_to, uint256 amount) public {
        require(msg.sender == OWNER, "only owner");

        require(
            (totalSupply() + amount) <= MAX_SUPPLY,
            "can not mint more than MAX_SUPPLY"
        );
        _mint(send_to, amount);
    }

    function changeOwner(address owner) public {
        require(msg.sender == OWNER, "only owner");
        OWNER = owner;
    }
}
