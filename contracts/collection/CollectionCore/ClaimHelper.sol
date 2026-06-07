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
    uint256 usdtPerNft
  );
  event Claimed(
    uint256 roundId,
    address account,
    uint256 tokenId,
    uint256 amount
  );

  /**
   * @notice Create and enable a claim round.
   *         Each round doubles supply per tokenId by allowing up to `maxMintsPerToken` new mints.
   * @param startTime Unix timestamp for the round start (must be >= block.timestamp).
   * @param usdtAmount Wei amount of USDT charged per minted token in this round.
   */
  function _enableMintAndClaim(uint128 startTime, uint256 usdtAmount) internal {
    require(startTime >= block.timestamp, "start must be future");
    require(usdtAmount > 0, "invalid USDT amount");

    uint256 roundId = ++claimRound;
    uint16 maxMintsPerToken =
      (roundId == 1) ? 1 : claimRounds[roundId - 1].maxMintsPerToken * 2;

    // Disable the previous round so only one round is active at a time.
    if (roundId > 1) {
      claimRounds[roundId - 1].isEnabled = false;
    }

    claimRounds[roundId] = ClaimRound({
      startTime: startTime,
      endTime: startTime + 30 days,
      usdtAmountPerNft: usdtAmount,
      maxMintsPerToken: maxMintsPerToken,
      isEnabled: true
    });

    emit ClaimRoundCreated(roundId, startTime, startTime + 30 days, usdtAmount);
  }

  /**
   * @dev Transfer USDT claim payment from the payer to the owner.
   */
  function _handleClaimPayment(
    address payer,
    uint256 price,
    uint256 quantity
  ) internal {
    uint256 amount = price * quantity;
    usdtToken.safeTransferFrom(payer, owner(), amount);
  }

  /**
   * @dev Mint tokens for a claim and update round accounting.
   */
  function _handleMintForClaim(
    address to,
    uint256 id,
    uint256 amount,
    uint256 roundId
  ) internal {
    // amount > 0 is guaranteed by both callers: _validateClaimTokens (require amount > 0)
    // and _handleOwnerClaim (require unclaimedAmount > 0).
    _mint(to, id, amount, "");
    mintedInRound[roundId][id] += amount;
    claimedPerRound[roundId][id][to] += amount;

    emit Claimed(roundId, to, id, amount);
  }

  /**
   * @notice Mint all remaining unclaimed tokens for a tokenId in a round to the owner.
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
    // No isEnabled check: claimTokens always validates `claimRound` (the latest round),
    // which is enabled by construction; only superseded rounds are ever disabled.
    require(
      currentTime >= round.startTime && currentTime <= round.endTime,
      "not in claim period"
    );

    uint256 alreadyClaimed = claimedPerRound[roundId][id][to];
    uint256 currentBalance = balanceOf(to, id);
    require(currentBalance >= alreadyClaimed, "inconsistent claimed state");

    // Pre-round balance excludes tokens minted during this round to prevent
    // a holder from using newly minted tokens to increase their claim entitlement.
    uint256 preRoundBalance = currentBalance - alreadyClaimed;
    require(preRoundBalance > 0, "must own token to claim");
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
   * @dev Revert unless the claim round's end time has passed.
   */
  function _onlyWhenDeadlinePassed(uint256 roundId) internal view {
    require(roundId > 0 && roundId <= claimRound, "invalid round id");
    require(
      claimRounds[roundId].endTime <= block.timestamp,
      "Deadline not passed"
    );
  }

  /**
   * @dev Return the number of tokens still available to claim for a tokenId in a round.
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
