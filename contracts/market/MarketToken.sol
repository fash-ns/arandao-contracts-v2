// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

import {ERC1155} from "@openzeppelin/contracts/token/ERC1155/ERC1155.sol";

contract DNMMintedProduct is ERC1155 {
  uint256 internal tokenIdSeq;
  address public mintOperator;
  address public deployer;

  mapping(uint256 => string) private ipfsCidList;

  constructor() ERC1155("") {
    tokenIdSeq = 1;
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
  }

  function isApprovedForAll(
    address account,
    address operator
  ) public view virtual override returns (bool) {
    return
      operator == mintOperator || super.isApprovedForAll(account, operator);
  }

  function setMintOperator(address _operator) public onlyDeployer {
    require(mintOperator == address(0), "Mint operator is already set.");
    mintOperator = _operator;
  }

  function mint(
    address account,
    uint256 amount,
    string memory ipfsCid
  ) public onlyMintOperator returns (uint256) {
    _mint(account, tokenIdSeq, amount, bytes(""));
    ipfsCidList[tokenIdSeq] = ipfsCid;
    return tokenIdSeq++;
  }

  function uri(
    uint256 tokenId
  ) public view virtual override returns (string memory) {
    return ipfsCidList[tokenId];
  }
}
