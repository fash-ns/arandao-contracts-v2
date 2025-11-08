// SPDX-License-Identifier: MIT
// Compatible with OpenZeppelin Contracts ^5.4.0
pragma solidity ^0.8.28;

import {ERC1155} from "@openzeppelin/contracts/token/ERC1155/ERC1155.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {CollectionStorage} from "./CollectionStorage.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

/**
 * @title ClaimHelper
 * @dev Provides functionality to manage claim rounds and handle token claims.
 */
abstract contract ClaimHelper is Ownable, ERC1155, CollectionStorage {
  using SafeERC20 for IERC20;

  event ClaimRoundCreated(
    uint256 roundId,
    uint128 startTime,
    uint128 endTime,
    uint256 daiPerNft
  );
  event Claimed(
    uint256 roundId,
    address account,
    uint256 tokenId,
    uint256 amount
  );

  /**
   * @notice Create and enable a claim round. Each round doubles supply per tokenId by allowing up to `totalSupply[tokenId]` new mints.
   * @param startTime unix seconds start
   * @param daiAmount wei amount of DAI charged per minted token in this round
   */
  function _enableMintAndClaim(uint128 startTime, uint256 daiAmount) internal {
    require(startTime >= block.timestamp, "start must be future");
    require(daiAmount > 0, "invalid DAI amount");

    uint256 roundId = ++claimRound;
    uint16 maxMintsPerToken = (roundId == 1)
      ? 1
      : claimRounds[roundId - 1].maxMintsPerToken * 2;

    // Disable previous round if exists
    if (roundId > 1) {
      claimRounds[roundId - 1].isEnabled = false;
    }

    claimRounds[roundId] = ClaimRound({
      startTime: startTime,
      endTime: startTime + 30 days,
      daiAmountPerNft: daiAmount,
      maxMintsPerToken: maxMintsPerToken,
      isEnabled: true
    });

    emit ClaimRoundCreated(roundId, startTime, startTime + 30 days, daiAmount);
  }

  /**
   * @dev Handle payment for claims by transferring DAI from payer to owner.
   */
  function _handleClaimPayment(
    address payer,
    uint256 price,
    uint256 quantity
  ) internal {
    uint256 amount = price * quantity;
    daiToken.safeTransferFrom(payer, owner(), amount);
  }

  /**
   * @dev Handle minting for claims by updating state and minting tokens.
   */
  function _handleMintForClaim(
    address to,
    uint256 id,
    uint256 amount,
    uint256 roundId
  ) internal {
    require(amount > 0, "invalid mint amount");

    _mint(to, id, amount, "");
    mintedInRound[roundId][id] += amount;
    claimedPerRound[roundId][id][to] += amount;

    emit Claimed(roundId, to, id, amount);
  }

  /**
   * @notice Owner claims unclaimed tokens after a claim round has ended.
   * @param roundId ID of the claim round.
   * @param tokenId Token ID to claim unclaimed tokens for.
   */
  function _handleOwnerClaim(uint256 roundId, uint256 tokenId) internal {
    uint256 unclaimedAmount = _getRemainingToClaim(roundId, tokenId);
    require(unclaimedAmount > 0, "No unclaimed tokens");

    _handleMintForClaim(owner(), tokenId, unclaimedAmount, roundId);
  }

  /**
   * @dev Validate that the claim conditions are met for the given tokenId and amount.
   */
  function _validateClaimTokens(
    uint256 roundId,
    address to,
    uint256 id,
    uint256 amount
  ) internal view {
    require(amount > 0, "invalid amount");
    require(claimRound > 0, "no active round");
    ClaimRound memory round = claimRounds[roundId];
    uint256 currentTime = block.timestamp;
    require(round.isEnabled, "claiming disabled");
    require(
      currentTime >= round.startTime && currentTime <= round.endTime,
      "not in claim period"
    );

    uint256 alreadyClaimed = claimedPerRound[roundId][id][to];
    uint256 currentBalance = balanceOf(to, id);
    require(currentBalance >= alreadyClaimed, "inconsistent claimed state");

    // compute holder's pre-round balance as: currentBalance - alreadyClaimed
    // that prevents using tokens minted during this round to increase entitlement
    uint256 preRoundBalance = currentBalance - alreadyClaimed;
    require(preRoundBalance > 0, "must own token to claim");

    // total claimed (alreadyClaimed + amount) must not exceed preRoundBalance
    require(
      alreadyClaimed + amount <= preRoundBalance,
      "already claimed max for holder"
    );

    uint256 totalMinted = mintedInRound[roundId][id];
    require(
      totalMinted + amount <= round.maxMintsPerToken,
      "exceeds claim limit"
    );
  }

  /**
   * @notice check the round deadline passed then owner can claim
   */
  function _onlyWhenDeadlinePassed(uint256 roundId) internal view {
    require(roundId > 0 && roundId <= claimRound, "invalid round id");
    require(
      claimRounds[roundId].endTime <= block.timestamp,
      "Deadline not passed"
    );
  }

  /**
   * @dev Get the remaining number of tokens that can be claimed for a given tokenId in a claim round.
   */
  function _getRemainingToClaim(
    uint256 roundId,
    uint256 tokenId
  ) internal view returns (uint256) {
    uint256 max = claimRounds[roundId].maxMintsPerToken;
    uint256 already = mintedInRound[roundId][tokenId];
    if (already >= max) return 0;
    return max - already;
  }
}
