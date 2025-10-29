// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

import {ERC1155} from "@openzeppelin/contracts/token/ERC1155/ERC1155.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

contract AranDAOMarketToken is ERC1155, Ownable {
  uint256 internal tokenIdSeq;
  mapping(uint256 => string) private ipfsCidList;
  mapping(address => bool) public isMintOperator;

  constructor() ERC1155("") Ownable(msg.sender) {
    tokenIdSeq = 1;
  }

  function isApprovedForAll(
    address account,
    address operator
  ) public view virtual override returns (bool) {
    return
      isMintOperator[operator] || super.isApprovedForAll(account, operator);
  }

  function setMintOperator(
    address _operator,
    bool _isMintOperator
  ) public onlyOwner {
    isMintOperator[_operator] = _isMintOperator;
  }

  modifier onlyMintOperator() {
    require(isMintOperator[msg.sender], "Only mint operator can mint");
    _;
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
