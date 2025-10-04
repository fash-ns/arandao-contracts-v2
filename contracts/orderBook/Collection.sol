// SPDX-License-Identifier: MIT
// Compatible with OpenZeppelin Contracts ^5.4.0
pragma solidity ^0.8.27;

import {ERC721} from "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import {ERC721URIStorage} from "@openzeppelin/contracts/token/ERC721/extensions/ERC721URIStorage.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

contract MyToken is ERC721, ERC721URIStorage, Ownable {
  /// @notice Flag to allow ownership transfer only once.
  bool public ownershipFlag;

  uint256 public nextTokenId;
  uint256 public constant MAX_SUPPLY = 1000;

  mapping(address => bool) public transferAllowed;

  constructor(
    address initialOwner
  ) ERC721("NFTFundraise", "NFR") Ownable(initialOwner) {
    nextTokenId++;
  }

  function safeMint(address to, string memory uri) external onlyOwner {
    _internalMint(to, uri);
  }

  function safeBatchMint(
    address[] calldata to,
    string[] calldata uris
  ) external onlyOwner {
    require(to.length == uris.length, "Mismatched arrays");
    for (uint256 i = 0; i < to.length; i++) {
      _internalMint(to[i], uris[i]);
    }
  }

  function addTransferAllowedAddress(address newAddress) external onlyOwner {
    require(newAddress != address(0), "Invalid address");
    require(!transferAllowed[newAddress], "Already authorized");
    transferAllowed[newAddress] = true;
  }

  function removeTransferAllowedAddress(address addr) external onlyOwner {
    require(transferAllowed[addr], "Not authorized");
    transferAllowed[addr] = false;
  }

  function _update(
    address to,
    uint256 tokenId,
    address auth
  ) internal override returns (address) {
    address from = _ownerOf(tokenId);
    require(
      transferAllowed[from] ||
        transferAllowed[to] ||
        transferAllowed[msg.sender] ||
        from == address(0),
      "Not allowed to transfer"
    );
    return super._update(to, tokenId, auth);
  }

  function _internalMint(address to, string memory uri) internal {
    uint256 tokenId = nextTokenId++;
    require(tokenId <= MAX_SUPPLY, "Max supply reached");
    _safeMint(to, tokenId);
    _setTokenURI(tokenId, uri);
  }

  /// @notice Transfers contract ownership to a new address, but only once.
  /// @dev Uses `ownershipFlag` to ensure ownership can only be transferred a single time.
  function transferOwnership(address newOwner) public override onlyOwner {
    if (ownershipFlag == false) {
      super.transferOwnership(newOwner);
      ownershipFlag = true;
    } else {
      revert("Ownership has already been transferred");
    }
  }

  // The following functions are overrides required by Solidity.

  function tokenURI(
    uint256 tokenId
  ) public view override(ERC721, ERC721URIStorage) returns (string memory) {
    return super.tokenURI(tokenId);
  }

  function supportsInterface(
    bytes4 interfaceId
  ) public view override(ERC721, ERC721URIStorage) returns (bool) {
    return super.supportsInterface(interfaceId);
  }
}
