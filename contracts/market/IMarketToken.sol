// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;
import {IERC1155} from "@openzeppelin/contracts/token/ERC1155/IERC1155.sol";
import {IERC1155MetadataURI} from "@openzeppelin/contracts/token/ERC1155/extensions/IERC1155MetadataURI.sol";
import {IERC1155Errors} from "@openzeppelin/contracts/interfaces/draft-IERC6093.sol";

interface IMarketToken is IERC1155, IERC1155MetadataURI, IERC1155Errors {
  function setMintOperator(address _operator, bool _isMintOperator) external;

  function mint(
    address account,
    uint256 amount,
    string memory ipfsCid
  ) external returns (uint256);
}
