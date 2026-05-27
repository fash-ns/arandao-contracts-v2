// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

import {ERC1155} from "@openzeppelin/contracts/token/ERC1155/ERC1155.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

contract DNMMintedProduct is ERC1155, Ownable {
  uint256 internal tokenIdSeq;
  address public mintOperator;
  mapping(uint256 => string) private ipfsCidList;
  bool ownershipFlag;

  constructor() ERC1155("") Ownable(msg.sender) {
    tokenIdSeq = 1;
  }

  function isApprovedForAll(
    address account,
    address operator
  ) public view virtual override returns (bool) {
    return
      operator == mintOperator || super.isApprovedForAll(account, operator);
  }

  function setMintOperator(address _operator) public onlyOwner {
    require(mintOperator == address(0), "Mint operator is already set.");
    mintOperator = _operator;
  }

  modifier onlyMintOperator() {
    require(mintOperator == msg.sender, "Only mint operator can mint");
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

  /**
   * @dev Override transferOwnership to allow only one transfer.
   */
  function transferOwnership(address newOwner) public override onlyOwner {
    if (ownershipFlag == false) {
      super.transferOwnership(newOwner);
      ownershipFlag = true;
    } else {
      revert("Ownership has already been transferred");
    }
  }
}
