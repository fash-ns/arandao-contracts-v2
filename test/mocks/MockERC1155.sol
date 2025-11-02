// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import {ERC1155} from "@openzeppelin/contracts/token/ERC1155/ERC1155.sol";

contract MockERC1155 is ERC1155 {
    constructor(string memory uri_) ERC1155(uri_) {}

    /// @notice Mint tokens to an address
    function mint(address to, uint256 id, uint256 amount, bytes memory data) external {
        _mint(to, id, amount, data);
    }
}
