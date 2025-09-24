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
    BridgeLib.validateDeadline(constructionTime);
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
    BridgeLib.validateArrayLengths(addresses.length, amounts.length, "Address and amount length mismatch.");
    for (uint256 i = 0; i < addresses.length; i++) {
      dnmBalanceByAddressSnapshot[addresses[i]] = amounts[i];
    }
  }

  function snapshotUvm(
    address[] memory addresses,
    uint256[] memory amounts
  ) public onlyOwner {
    BridgeLib.validateArrayLengths(addresses.length, amounts.length, "Address and amount length mismatch.");
    for (uint256 i = 0; i < addresses.length; i++) {
      uvmBalanceByAddressSnapshot[addresses[i]] = amounts[i];
    }
  }

  function snapshotWrapperToken(
    address[] memory addresses,
    uint256[][] memory tokenIds
  ) public onlyOwner {
    BridgeLib.validateArrayLengths(addresses.length, tokenIds.length, "Address and tokenId length mismatch.");
    for (uint256 i = 0; i < addresses.length; i++) {
      wrapperTokenIdsByAddressSnapshot[addresses[i]] = tokenIds[i];
    }
  }

  function snapshotArusanseToken(
    address[] memory addresses,
    uint256[][] memory tokenIds
  ) public onlyOwner {
    BridgeLib.validateArrayLengths(addresses.length, tokenIds.length, "Address and tokenId length mismatch.");
    for (uint256 i = 0; i < addresses.length; i++) {
      arusenseTokenIdsByAddressSnapshot[addresses[i]] = tokenIds[i];
    }
  }

  function withdrawDnm(uint256 amount) public onlyOwner {
    require(
      amount <= dnmBalance,
      "Amount is greater than the contract's DNM balance."
    );
    BridgeLib.transferERC20From(
      oldDnmAddress,
      address(this),
      msg.sender,
      amount,
      "DNM transfer from contract to user wasn't successful."
    );
    dnmBalance -= amount;
  }

  function withdrawRemainingNewDnm() public onlyOwner {
    uint256 contractBalance = BridgeLib.getERC20Balance(newDnmAddress, address(this));
    BridgeLib.transferERC20From(
      newDnmAddress,
      address(this),
      msg.sender,
      contractBalance,
      "DNM transfer from contract to user wasn't successful."
    );
  }

  function withdrawUvm(uint256 amount) public onlyOwner {
    require(
      amount <= uvmBalance,
      "Amount is greater than the contract's UVM balance."
    );
    BridgeLib.transferERC20From(
      oldUvmAddress,
      address(this),
      msg.sender,
      amount,
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
    uint256 userBalance = BridgeLib.getERC20Balance(oldUvmAddress, msg.sender);
    uint256 bridgedBalance = BridgeLib.validateBridgeAmount(
      uvmBalanceByAddressSnapshot[msg.sender],
      userBalance
    );

    BridgeLib.transferERC20From(
      oldUvmAddress,
      msg.sender,
      address(this),
      bridgedBalance,
      "UVM transfer from user to contract wasn't successful."
    );
    uvmBalance += bridgedBalance;
    uvmBalanceByAddressSnapshot[msg.sender] -= bridgedBalance;

    uint256 dnmAmount = BridgeLib.calculateDnmFromUvm(bridgedBalance);
    BridgeLib.transferERC20From(
      newDnmAddress,
      address(this),
      msg.sender,
      dnmAmount,
      "DNM transfer from contract to user wasn't successful."
    );
  }

  function bridgeDnm() public inDeadlineDuration {
    uint256 userBalance = BridgeLib.getERC20Balance(oldDnmAddress, msg.sender);
    uint256 bridgedBalance = BridgeLib.validateBridgeAmount(
      dnmBalanceByAddressSnapshot[msg.sender],
      userBalance
    );

    BridgeLib.transferERC20From(
      oldDnmAddress,
      msg.sender,
      address(this),
      bridgedBalance,
      "DNM transfer from user to contract wasn't successful."
    );
    dnmBalance += bridgedBalance;
    dnmBalanceByAddressSnapshot[msg.sender] -= bridgedBalance;

    BridgeLib.transferERC20From(
      newDnmAddress,
      address(this),
      msg.sender,
      bridgedBalance,
      "DNM transfer from contract to user wasn't successful."
    );
  }

  function bridgeArusenseNFT(uint256 tokenId) public inDeadlineDuration {
    uint256[] memory tokenIds = arusenseTokenIdsByAddressSnapshot[msg.sender];
    require(
      BridgeLib.validateTokenExistsInArray(tokenId, tokenIds),
      "Token doesn't exist in the snapshot."
    );

    BridgeLib.validateTokenOwnership(oldArusenseAddress, tokenId, msg.sender);

    INFTLandMarket arusenseMarketContract = INFTLandMarket(oldArusenseMarketAddress);
    (uint256 bv, uint256 sv) = arusenseMarketContract.getMintPrice(tokenId);
    IERC721(oldArusenseAddress).safeTransferFrom(msg.sender, address(this), tokenId);

    uint256 dnmAmount = BridgeLib.calculateDnmFromPrices(bv, sv);
    BridgeLib.transferERC20From(
      newDnmAddress,
      address(this),
      msg.sender,
      dnmAmount,
      "DNM transfer from contract to user wasn't successful."
    );

    arusenseTokenIds.push(tokenId);
  }

  function bridgeWrapperToken(uint256 tokenId) public inDeadlineDuration {
    IWrapper wrapperTokenContract = IWrapper(oldWrapperTokenAddress);
    uint256[] memory tokenIds = wrapperTokenIdsByAddressSnapshot[msg.sender];
    require(
      BridgeLib.validateTokenExistsInArray(tokenId, tokenIds),
      "Token doesn't exist in the snapshot."
    );

    BridgeLib.validateTokenOwnership(oldWrapperTokenAddress, tokenId, msg.sender);

    uint256 arusenseTokenId = wrapperTokenContract.wrapTokenList(tokenId).token_id;
    INFTLandMarket arusenseMarketContract = INFTLandMarket(oldArusenseMarketAddress);
    (uint256 bv, uint256 sv) = arusenseMarketContract.getMintPrice(arusenseTokenId);
    wrapperTokenContract.safeTransferFrom(msg.sender, address(this), tokenId);

    uint256 dnmAmount = BridgeLib.calculateDnmFromPrices(bv, sv);
    BridgeLib.transferERC20From(
      newDnmAddress,
      address(this),
      msg.sender,
      dnmAmount,
      "DNM transfer from contract to user wasn't successful."
    );

    wrapperTokenIds.push(tokenId);
  }

  function bridgeStakePrinciple(uint256 stakeId) public {
    BridgeLib.Stake memory stake = stakeSnapshot[stakeId];
    BridgeLib.validateStakeExists(stake);
    BridgeLib.validateStakePrincipleNotWithdrawn(stake);

    IStakeMeta stakeContract = IStakeMeta(oldStakeAddress);
    IStakeMeta.StakePlan memory stakePlan = stakeContract.getStake(stakeId);

    BridgeLib.validateStakeClosed(stakePlan.finish);

    uint256 eligibleTimestamp = BridgeLib.calculateEligibilityTimestamp(
      stakePlan.start,
      stakePlan.stake_duration,
      constructionTime,
      30
    );
    require(
      block.timestamp >= eligibleTimestamp,
      "The time for principle withdrawal of this stake has been passed."
    );

    BridgeLib.transferERC20From(
      oldUvmAddress,
      stake.userAddress,
      address(this),
      stakePlan.uvm,
      "UVM transfer from user to contract wasn't successful."
    );
    uvmBalance += stakePlan.uvm;

    BridgeLib.transferERC20From(
      oldDnmAddress,
      stake.userAddress,
      address(this),
      stakePlan.dnm,
      "Previous DNM transfer from user to contract wasn't successful."
    );
    dnmBalance += stakePlan.dnm;

    IWrapper wrapperTokenContract = IWrapper(oldWrapperTokenAddress);
    uint256 arusenseTokenId = wrapperTokenContract.wrapTokenList(stakePlan.land).token_id;
    INFTLandMarket arusenseMarketContract = INFTLandMarket(oldArusenseMarketAddress);
    (uint256 bv, uint256 sv) = arusenseMarketContract.getMintPrice(arusenseTokenId);
    wrapperTokenContract.safeTransferFrom(msg.sender, address(this), stakePlan.land);

    wrapperTokenIds.push(stakePlan.land);

    uint256 landDnmAmount = BridgeLib.calculateDnmFromPrices(bv, sv);
    BridgeLib.transferERC20From(
      newDnmAddress,
      address(this),
      msg.sender,
      landDnmAmount,
      "New DNM transfer from contract to user wasn't successful."
    );

    stakeSnapshot[stakeId].principleWithdrawn = true;
  }

  function bridgeStakeYield(uint256 stakeId, uint256 uvmAmount) public {
    BridgeLib.Stake memory stake = stakeSnapshot[stakeId];
    BridgeLib.validateStakeExists(stake);
    BridgeLib.validateStakePrincipleNotWithdrawn(stake);

    IStakeMeta stakeContract = IStakeMeta(oldStakeAddress);
    IStakeMeta.StakePlan memory stakePlan = stakeContract.getStake(stakeId);

    BridgeLib.validateStakeClosed(stakePlan.finish);

    uint256 eligibleTimestamp = BridgeLib.calculateEligibilityTimestamp(
      stakePlan.finish,
      300 days,
      constructionTime + 30 days,
      30
    );

    require(
      block.timestamp >= eligibleTimestamp,
      "The time for yield withdrawal of this stake has been passed."
    );

    uint256 totalReward = stakeContract.calculateReward(
      stakePlan.plan,
      stakePlan.dnm,
      stakePlan.start,
      stakePlan.finish,
      stakePlan.stake_duration
    );

    BridgeLib.validateYieldAmount(uvmAmount, totalReward, stake.totalPaidOut);

    BridgeLib.transferERC20From(
      oldUvmAddress,
      stake.userAddress,
      address(this),
      uvmAmount,
      "UVM transfer from user to contract wasn't successful."
    );

    uvmBalance += uvmAmount;
    stake.totalPaidOut += uvmAmount;

    uint256 dnmAmount = BridgeLib.calculateDnmFromUvm(uvmAmount);
    BridgeLib.transferERC20From(
      newDnmAddress,
      address(this),
      msg.sender,
      dnmAmount,
      "New DNM transfer from contract to user wasn't successful."
    );
  }
}
