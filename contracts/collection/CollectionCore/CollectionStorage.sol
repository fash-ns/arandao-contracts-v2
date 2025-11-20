// SPDX-License-Identifier: MIT
// Compatible with OpenZeppelin Contracts ^5.4.0
pragma solidity ^0.8.28;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

abstract contract CollectionStorage {
  /// @notice Flag to allow ownership transfer only once.
  bool public ownershipFlag;

  /// @notice Address of the order book contract.
  address public orderBookAddress;

  /// @notice Deadline timestamp after which upgrades are disabled.
  uint256 public upgradeDeadline;

  /// @notice index of next claim round (0-based). When creating a round we store it at claimRound and then increment.
  uint256 public claimRound;

  // Flag to disable setURI function permanently
  bool isSetUriDisabled;

  bool isInitialMintEnable;

  bool canUpdateTransferAllowedList;

  IERC20 public daiToken;

  struct ClaimRound {
    uint128 startTime;
    uint128 endTime;
    uint256 daiAmountPerNft; // wei units of DAI per minted token
    uint16 maxMintsPerToken; // not used in current doubling logic but kept for flexibility
    bool isEnabled;
  }

  /// @notice Mapping from roundId to ClaimRound details
  mapping(uint256 => ClaimRound) public claimRounds;

  /// @notice Mapping from roundId and tokenId to the number of tokens minted in that round for that tokenId
  mapping(uint256 => mapping(uint256 => uint256)) public mintedInRound;

  /// @notice Mapping from roundId, tokenId, and account to the number of tokens claimed by that account in that round for that tokenId
  mapping(uint256 => mapping(uint256 => mapping(address => uint256)))
    public claimedPerRound;

  /// @notice Mapping from tokenId to token URI
  mapping(uint256 => string) internal _tokenURIs;
}
