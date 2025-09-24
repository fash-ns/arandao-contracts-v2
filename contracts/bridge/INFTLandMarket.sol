// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

interface INFTLandMarket {
  function setToken(uint8 token_id) external;
  function changeMaxId(uint256 max_id) external;
  function mint(uint256[] memory _tokenIds, address parent) external;
  function getMintPrice(
    uint256 land_id
  ) external view returns (uint256 bv, uint256 sv);
}
