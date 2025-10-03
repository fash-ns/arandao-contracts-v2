// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IERC721} from "@openzeppelin/contracts/token/ERC721/IERC721.sol";

library BridgeLib {
  struct Stake {
    address userAddress;
    bool exists;
    uint256 totalPaidOut;
    bool principleWithdrawn;
  }

  event GotDnmSnapshot();
  event GotUvmSnapshot();
  event GotArusenseSnapshot();
  event GotWrapperSnapshot();
  event GotStakeSnapshot();
  event DnmWithdrawnByOwner(uint256 amount);
  event RemainingNewDnmWithdrawnByOwner(uint256 amount);
  event UvmWithdrawnByOwner(uint256 amount);
  event ArusenseTokenWithdrawnByOwner(uint256 tokenId);
  event WrapperTokenWithdrawnByOwner(uint256 tokenId);
  event UvmBridgedByUser(
    address userAddress,
    uint256 amount,
    uint256 totalBridgedDnm
  );
  event DnmBridgedByUser(
    address userAddress,
    uint256 amount,
    uint256 totalBridgedDnm
  );
  event ArusenseTokenBridgedByUser(
    address userAddress,
    uint256 tokenId,
    uint256 totalBridgedDnm
  );
  event WrapperTokenBridgedByUser(
    address userAddress,
    uint256 tokenId,
    uint256 totalBridgedDnm
  );
  event StakePrincipleBridgedByUser(
    address userAddress,
    uint256 stakeId,
    uint256 uvmAmount,
    uint256 dnmAmount,
    uint256 wrapperTokenId,
    uint256 totalBridgedDnm
  );
  event StakeYieldBridgedByUser(
    address userAddress,
    uint256 stakeId,
    uint256 uvmAmount,
    uint256 totalBridgedDnm
  );

  // Math utility functions
  function getMax(uint256 a, uint256 b) internal pure returns (uint256) {
    return a >= b ? a : b;
  }

  function getMin(uint256 a, uint256 b) internal pure returns (uint256) {
    return a >= b ? b : a;
  }

  // Validation functions
  function validateArrayLengths(
    uint256 len1,
    uint256 len2,
    string memory errorMessage
  ) internal pure {
    require(len1 == len2, errorMessage);
  }

  function validateTokenExistsInArray(
    uint256 tokenId,
    uint256[] memory tokenIds
  ) internal pure returns (bool) {
    uint256 tokenIdsLen = tokenIds.length;
    for (uint256 i = 0; i < tokenIdsLen; i++) {
      if (tokenIds[i] == tokenId) {
        return true;
      }
    }
    return false;
  }

  function validateTokenOwnership(
    address tokenContract,
    uint256 tokenId,
    address expectedOwner
  ) internal view {
    address tokenOwner = IERC721(tokenContract).ownerOf(tokenId);
    require(
      tokenOwner == expectedOwner,
      "User is not the owner of the provided token."
    );
  }

  function validateDeadline(uint256 constructionTime) internal view {
    require(
      block.timestamp < constructionTime + (30 days),
      "The time to bridge has been past."
    );
  }

  // Calculation functions
  function calculateDnmFromPrices(
    uint256 bv,
    uint256 sv
  ) internal pure returns (uint256) {
    return (bv + (sv * 1e12)) / 1000;
  }

  function calculateDnmFromUvm(
    uint256 uvmAmount
  ) internal pure returns (uint256) {
    return uvmAmount / 10000;
  }

  function calculateNewDnmFromOldDnm(
    uint256 uvmAmount
  ) internal pure returns (uint256) {
    return uvmAmount / 10;
  }

  function calculateEligibilityTimestamp(
    uint256 baseTimestamp,
    uint256 duration,
    uint256 constructionTime,
    uint256 additionalDays
  ) internal pure returns (uint256) {
    return
      getMax(baseTimestamp + duration, constructionTime) +
      (additionalDays * 1 days);
  }

  // Token transfer functions
  function transferERC20From(
    address tokenContract,
    address from,
    address to,
    uint256 amount,
    string memory errorMessage
  ) internal {
    bool success = IERC20(tokenContract).transferFrom(from, to, amount);
    require(success, errorMessage);
  }

  function transferERC20(
    address tokenContract,
    address to,
    uint256 amount,
    string memory errorMessage
  ) internal {
    bool success = IERC20(tokenContract).transfer(to, amount);
    require(success, errorMessage);
  }

  function getERC20Balance(
    address tokenContract,
    address account
  ) internal view returns (uint256) {
    return IERC20(tokenContract).balanceOf(account);
  }

  // Bridge validation functions
  function validateBridgeAmount(
    uint256 snapshotAmount,
    uint256 userBalance
  ) internal pure returns (uint256) {
    uint256 bridgedBalance = getMin(snapshotAmount, userBalance);
    require(bridgedBalance > 0, "User doesn't have any bridgable tokens.");
    return bridgedBalance;
  }

  function validateStakeExists(Stake memory stake) internal pure {
    require(stake.exists, "This stake doesn't exist in snapshot.");
  }

  function validateStakePrincipleNotWithdrawn(
    Stake memory stake
  ) internal pure {
    require(
      !stake.principleWithdrawn,
      "This stake's principle has already been withdrawn."
    );
  }

  function validateStakeClosed(uint256 finishTime) internal pure {
    require(finishTime != 0, "This stake is not closed yet.");
  }

  function validateYieldAmount(
    uint256 requestedAmount,
    uint256 totalReward,
    uint256 totalPaidOut
  ) internal pure {
    require(
      requestedAmount <= totalReward - totalPaidOut,
      "Entered UVM amount is greater than the total remaining reward of the stake."
    );
  }

  function getUvmAmountByWrapperTokenType(
    uint8 _type
  ) internal pure returns (uint256) {
    if (_type == 1) {
      return 680 ether;
    } else if (_type == 2) {
      return 340 ether;
    } else if (_type == 3) {
      return 170 ether;
    } else if (_type == 4) {
      return 68 ether;
    } else if (_type == 5) {
      return 34 ether;
    } else {
      revert("Type should be in range 1 - 5");
    }
  }
}
