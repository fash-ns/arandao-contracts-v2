// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IERC721} from "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import {INFTLandMarket} from "./INFTLandMarket.sol";
import {IWrapper} from "./IWrapper.sol";
import {IStakeMeta} from "./IStakeMeta.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {BridgeLib} from "./BridgeLib.sol";

contract AranDAOBridge is Ownable {
  address public oldUvmAddress;
  address public oldDnmAddress;
  address public oldArusenseAddress;
  address public oldArusenseMarketAddress;
  address public oldWrapperTokenAddress;
  address public oldStakeAddress;
  address public newDnmAddress;
  uint256 public constructionTime;

  uint256 public uvmBalance;
  uint256 public dnmBalance;
  uint256[] public arusenseTokenIds;
  uint256[] public wrapperTokenIds;

  mapping(address => uint256) public uvmBalanceByAddressSnapshot;
  mapping(address => uint256) public dnmBalanceByAddressSnapshot;
  mapping(address => uint256[]) public arusenseTokenIdsByAddressSnapshot;
  mapping(address => uint256[]) public wrapperTokenIdsByAddressSnapshot;
  mapping(uint256 => BridgeLib.Stake) public stakeSnapshot;

  modifier inDeadlineDuration() {
    require(
      block.timestamp < constructionTime + (30 days),
      "The time to bridge has been past."
    );
    _;
  }

  constructor(
    address _oldUvmAddress,
    address _oldDnmAddress,
    address _oldArusenseAddress,
    address _oldArusenseMarketAddress,
    address _oldWrapperTokenAddress,
    address _oldStakeAddress,
    address _newDnmAddress
  ) Ownable(msg.sender) {
    oldUvmAddress = _oldUvmAddress;
    oldDnmAddress = _oldDnmAddress;
    oldArusenseAddress = _oldArusenseAddress;
    oldArusenseMarketAddress = _oldArusenseMarketAddress;
    oldWrapperTokenAddress = _oldWrapperTokenAddress;
    oldStakeAddress = _oldStakeAddress;
    newDnmAddress = _newDnmAddress;
    constructionTime = block.timestamp;
  }

  function snapshotDnm(
    address[] memory addresses,
    uint256[] memory amounts
  ) public onlyOwner {
    uint256 addressLen = addresses.length;
    uint256 amountLen = amounts.length;
    require(addressLen == amountLen, "Address and amount length mismatch.");
    for (uint256 i = 0; i < addressLen; i++) {
      dnmBalanceByAddressSnapshot[addresses[i]] = amounts[i];
    }
  }

  function snapshotUvm(
    address[] memory addresses,
    uint256[] memory amounts
  ) public onlyOwner {
    uint256 addressLen = addresses.length;
    uint256 amountLen = amounts.length;
    require(addressLen == amountLen, "Address and amount length mismatch.");
    for (uint256 i = 0; i < addressLen; i++) {
      uvmBalanceByAddressSnapshot[addresses[i]] = amounts[i];
    }
  }

  function snapshotWrapperToken(
    address[] memory addresses,
    uint256[][] memory tokenIds
  ) public onlyOwner {
    uint256 addressLen = addresses.length;
    uint256 tokenIdsLen = tokenIds.length;
    require(addressLen == tokenIdsLen, "Address and tokenId length mismatch.");
    for (uint256 i = 0; i < addressLen; i++) {
      wrapperTokenIdsByAddressSnapshot[addresses[i]] = tokenIds[i];
    }
  }

  function snapshotArusanseToken(
    address[] memory addresses,
    uint256[][] memory tokenIds
  ) public onlyOwner {
    uint256 addressLen = addresses.length;
    uint256 tokenIdsLen = tokenIds.length;
    require(addressLen == tokenIdsLen, "Address and tokenId length mismatch.");
    for (uint256 i = 0; i < addressLen; i++) {
      arusenseTokenIdsByAddressSnapshot[addresses[i]] = tokenIds[i];
    }
  }

  function withdrawDnm(uint256 amount) public onlyOwner {
    require(
      amount <= dnmBalance,
      "Amount is greater than the contract's DNM balance."
    );
    IERC20 dnmContract = IERC20(oldDnmAddress);
    bool isDnmTransferSuccessful = dnmContract.transferFrom(
      address(this),
      msg.sender,
      amount
    );
    require(
      isDnmTransferSuccessful,
      "DNM transfer from contract to user wasn't successful."
    );
    dnmBalance -= amount;
  }

  function withdrawRemainingNewDnm() public onlyOwner {
    IERC20 newDnmContract = IERC20(newDnmAddress);
    uint256 contractBalance = newDnmContract.balanceOf(address(this));
    bool isDnmTransferSuccessful = newDnmContract.transferFrom(
      address(this),
      msg.sender,
      contractBalance
    );
    require(
      isDnmTransferSuccessful,
      "DNM transfer from contract to user wasn't successful."
    );
  }

  function withdrawUvm(uint256 amount) public onlyOwner {
    require(
      amount <= uvmBalance,
      "Amount is greater than the contract's UVM balance."
    );
    IERC20 uvmContract = IERC20(oldUvmAddress);
    bool isUvmTransferSuccessful = uvmContract.transferFrom(
      address(this),
      msg.sender,
      amount
    );
    require(
      isUvmTransferSuccessful,
      "UVM transfer from contract to user wasn't successful."
    );
    uvmBalance -= amount;
  }

  function withdrawArusenseToken(uint256 tokenId) public onlyOwner {
    IERC721 arusenseContract = IERC721(oldArusenseAddress);
    arusenseContract.transferFrom(address(this), msg.sender, tokenId);
  }

  function withdrawWrapperToken(uint256 tokenId) public onlyOwner {
    IWrapper wrapperTokenContract = IWrapper(oldWrapperTokenAddress);
    wrapperTokenContract.transferFrom(address(this), msg.sender, tokenId);
  }

  function bridgeUvm() public inDeadlineDuration {
    IERC20 uvmContract = IERC20(oldUvmAddress);
    uint256 userBalance = uvmContract.balanceOf(msg.sender);

    uint256 bridgedBalance = BridgeLib.getMin(
      uvmBalanceByAddressSnapshot[msg.sender],
      userBalance
    );
    require(bridgedBalance > 0, "User doesn't have any bridgable UVM.");

    bool isUvmTransferSuccessful = uvmContract.transferFrom(
      msg.sender,
      address(this),
      bridgedBalance
    );
    require(
      isUvmTransferSuccessful,
      "UVM transfer from user to contract wasn't successful."
    );
    uvmBalance += bridgedBalance;
    uvmBalanceByAddressSnapshot[msg.sender] -= bridgedBalance;

    IERC20 newDnmContract = IERC20(newDnmAddress);
    bool isDnmTransferSuccessful = newDnmContract.transferFrom(
      address(this),
      msg.sender,
      bridgedBalance / 1000
    );
    require(
      isDnmTransferSuccessful,
      "DNM transfer from contract to user wasn't successful."
    );
  }

  function bridgeDnm() public inDeadlineDuration {
    IERC20 oldDnmContract = IERC20(oldDnmAddress);
    uint256 userBalance = oldDnmContract.balanceOf(msg.sender);

    uint256 bridgedBalance = BridgeLib.getMin(
      dnmBalanceByAddressSnapshot[msg.sender],
      userBalance
    );
    require(bridgedBalance > 0, "User doesn't have any bridgable DNM.");

    bool isOldDnmTransferSuccessful = oldDnmContract.transferFrom(
      msg.sender,
      address(this),
      bridgedBalance
    );
    require(
      isOldDnmTransferSuccessful,
      "DNM transfer from user to contract wasn't successful."
    );
    dnmBalance += bridgedBalance;
    dnmBalanceByAddressSnapshot[msg.sender] -= bridgedBalance;

    IERC20 newDnmContract = IERC20(newDnmAddress);
    bool isDnmTransferSuccessful = newDnmContract.transferFrom(
      address(this),
      msg.sender,
      bridgedBalance
    );
    require(
      isDnmTransferSuccessful,
      "DNM transfer from contract to user wasn't successful."
    );
  }

  function bridgeArusenseNFT(uint256 tokenId) public inDeadlineDuration {
    IERC721 arusenseContract = IERC721(oldArusenseAddress);
    uint256[] memory tokenIds = arusenseTokenIdsByAddressSnapshot[msg.sender];
    uint256 tokenIdsLen = tokenIds.length;
    bool tokenExists = false;
    for (uint256 i = 0; i < tokenIdsLen; i++) {
      if (tokenIds[i] == tokenId) {
        tokenExists = true;
        break;
      }
    }
    require(tokenExists, "Token doesn't exist in the snapshot.");

    address tokenOwner = arusenseContract.ownerOf(tokenId);
    require(
      tokenOwner == msg.sender,
      "User is not the owner of the provided arusense token."
    );

    INFTLandMarket arusenseMarketContract = INFTLandMarket(
      oldArusenseMarketAddress
    );
    (uint256 bv, uint256 sv) = arusenseMarketContract.getMintPrice(tokenId);
    arusenseContract.safeTransferFrom(msg.sender, address(this), tokenId);

    IERC20 newDnmContract = IERC20(newDnmAddress);
    bool isDnmTransferSuccessful = newDnmContract.transferFrom(
      address(this),
      msg.sender,
      (bv + (sv * 1e12)) / 1000
    );
    require(
      isDnmTransferSuccessful,
      "DNM transfer from contract to user wasn't successful."
    );

    arusenseTokenIds.push(tokenId);
  }

  function bridgeWrapperToken(uint256 tokenId) public inDeadlineDuration {
    IWrapper wrapperTokenContract = IWrapper(oldWrapperTokenAddress);
    uint256[] memory tokenIds = wrapperTokenIdsByAddressSnapshot[msg.sender];
    uint256 tokenIdsLen = tokenIds.length;
    bool tokenExists = false;
    for (uint256 i = 0; i < tokenIdsLen; i++) {
      if (tokenIds[i] == tokenId) {
        tokenExists = true;
        break;
      }
    }
    require(tokenExists, "Token doesn't exist in the snapshot.");

    address tokenOwner = wrapperTokenContract.ownerOf(tokenId);
    require(
      tokenOwner == msg.sender,
      "User is not the owner of the provided wrapper token."
    );

    uint256 arusenseTokenId = wrapperTokenContract
      .wrapTokenList(tokenId)
      .token_id;
    INFTLandMarket arusenseMarketContract = INFTLandMarket(
      oldArusenseMarketAddress
    );
    (uint256 bv, uint256 sv) = arusenseMarketContract.getMintPrice(
      arusenseTokenId
    );
    wrapperTokenContract.safeTransferFrom(msg.sender, address(this), tokenId);

    IERC20 newDnmContract = IERC20(newDnmAddress);
    bool isDnmTransferSuccessful = newDnmContract.transferFrom(
      address(this),
      msg.sender,
      (bv + (sv * 1e12)) / 1000
    );
    require(
      isDnmTransferSuccessful,
      "DNM transfer from contract to user wasn't successful."
    );

    wrapperTokenIds.push(tokenId);
  }

  function bridgeStakePrinciple(uint256 stakeId) public {
    BridgeLib.Stake memory stake = stakeSnapshot[stakeId];
    require(stake.exists, "This stake doesn't exist in snapshot.");
    require(
      !stake.principleWithdrawn,
      "This stake's principle has already been withdrawn."
    );

    IStakeMeta stakeContract = IStakeMeta(oldStakeAddress);
    IStakeMeta.StakePlan memory stakePlan = stakeContract.getStake(stakeId);

    require(stakePlan.finish != 0, "This stake is not closed yet.");

    uint256 eligibleTimestamp = BridgeLib.getMax(
      stakePlan.start + stakePlan.stake_duration,
      constructionTime
    );
    require(
      block.timestamp >= eligibleTimestamp + 30 days,
      "The time for principle withdrawal of this stake has been passed."
    );

    uint256 totalDnm = 0;

    IERC20 uvmContract = IERC20(oldUvmAddress);
    bool isUvmTransferSuccessful = uvmContract.transferFrom(
      stake.userAddress,
      address(this),
      stakePlan.uvm
    );
    require(
      isUvmTransferSuccessful,
      "UVM transfer from user to contract wasn't successful."
    );
    uvmBalance += stakePlan.uvm;
    totalDnm += (stakePlan.uvm / 1000);

    IERC20 dnmContract = IERC20(oldDnmAddress);
    bool isDnmTransferSuccessful = dnmContract.transferFrom(
      stake.userAddress,
      address(this),
      stakePlan.dnm
    );
    require(
      isDnmTransferSuccessful,
      "Previous DNM transfer from user to contract wasn't successful."
    );
    dnmBalance += stakePlan.dnm;
    totalDnm += stakePlan.dnm;

    IWrapper wrapperTokenContract = IWrapper(oldWrapperTokenAddress);
    uint256 arusenseTokenId = wrapperTokenContract
      .wrapTokenList(stakePlan.land)
      .token_id;
    INFTLandMarket arusenseMarketContract = INFTLandMarket(
      oldArusenseMarketAddress
    );
    (uint256 bv, uint256 sv) = arusenseMarketContract.getMintPrice(
      arusenseTokenId
    );
    wrapperTokenContract.safeTransferFrom(
      msg.sender,
      address(this),
      stakePlan.land
    );

    wrapperTokenIds.push(stakePlan.land);

    totalDnm += (bv + (sv * 1e12)) / 1000;

    IERC20 newDnmContract = IERC20(newDnmAddress);
    bool isNewDnmTransferSuccessful = newDnmContract.transferFrom(
      address(this),
      msg.sender,
      (bv + (sv * 1e12)) / 1000
    );
    require(
      isNewDnmTransferSuccessful,
      "New DNM transfer from contract to user wasn't successful."
    );

    stakeSnapshot[stakeId].principleWithdrawn = true;
  }

  function bridgeStakeYield(uint256 stakeId, uint256 uvmAmount) public {
    BridgeLib.Stake memory stake = stakeSnapshot[stakeId];
    require(stake.exists, "This stake doesn't exist in snapshot.");
    require(
      !stake.principleWithdrawn,
      "This stake's principle has already been withdrawn."
    );

    IStakeMeta stakeContract = IStakeMeta(oldStakeAddress);
    IStakeMeta.StakePlan memory stakePlan = stakeContract.getStake(stakeId);

    require(stakePlan.finish != 0, "This stake is not closed yet.");

    uint256 eligibleTimestamp = BridgeLib.getMax(
      stakePlan.finish + 300 days,
      constructionTime + 30 days
    );

    require(
      block.timestamp >= eligibleTimestamp + 30 days,
      "The time for yield withdrawal of this stake has been passed."
    );

    uint256 totalReward = stakeContract.calculateReward(
      stakePlan.plan,
      stakePlan.dnm,
      stakePlan.start,
      stakePlan.finish,
      stakePlan.stake_duration
    );

    require(
      uvmAmount <= totalReward - stake.totalPaidOut,
      "Entered UVM amount is greater than the total remaining reward of the stake."
    );

    IERC20 uvmContract = IERC20(oldUvmAddress);
    bool isUvmTransferSuccessful = uvmContract.transferFrom(
      stake.userAddress,
      address(this),
      uvmAmount
    );
    require(
      isUvmTransferSuccessful,
      "UVM transfer from user to contract wasn't successful."
    );

    uvmBalance += uvmAmount;
    stake.totalPaidOut += uvmAmount;

    IERC20 newDnmContract = IERC20(newDnmAddress);
    bool isNewDnmTransferSuccessful = newDnmContract.transferFrom(
      address(this),
      msg.sender,
      uvmAmount / 1000
    );
    require(
      isNewDnmTransferSuccessful,
      "New DNM transfer from contract to user wasn't successful."
    );
  }
}
