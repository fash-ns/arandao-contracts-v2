// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

import {IWrapper} from "./IWrapper.sol";
import {IStakeMeta} from "./IStakeMeta.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {BridgeLib} from "./BridgeLib.sol";
import {ERC721Holder} from "@openzeppelin/contracts/token/ERC721/utils/ERC721Holder.sol";

contract AranDAOBridge is Ownable, ERC721Holder {
  address public oldUvmAddress;
  address public oldDnmAddress;
  address public oldArusenseAddress;
  // address public oldArusenseMarketAddress;
  address public oldWrapperTokenAddress;
  address public oldStakeAddress;
  address public newDnmAddress;
  uint256 public constructionTime;

  uint256[] public arusenseTokenIds;
  uint256[] public wrapperTokenIds;

  mapping(address => uint256) public uvmBalanceByAddressSnapshot;
  mapping(address => uint256) public dnmBalanceByAddressSnapshot;
  // mapping(address => uint256[]) public arusenseTokenIdsByAddressSnapshot;
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
    // address _oldArusenseMarketAddress,
    address _oldWrapperTokenAddress,
    address _oldStakeAddress,
    address _newDnmAddress
  ) Ownable(msg.sender) {
    oldUvmAddress = _oldUvmAddress;
    oldDnmAddress = _oldDnmAddress;
    oldArusenseAddress = _oldArusenseAddress;
    // oldArusenseMarketAddress = _oldArusenseMarketAddress;
    oldWrapperTokenAddress = _oldWrapperTokenAddress;
    oldStakeAddress = _oldStakeAddress;
    newDnmAddress = _newDnmAddress;
    constructionTime = block.timestamp;
  }

  function snapshotDnm(
    address[] memory addresses,
    uint256[] memory amounts
  ) public onlyOwner {
    BridgeLib.validateArrayLengths(
      addresses.length,
      amounts.length,
      "Address and amount length mismatch."
    );
    for (uint256 i = 0; i < addresses.length; i++) {
      dnmBalanceByAddressSnapshot[addresses[i]] = amounts[i];
    }
    emit BridgeLib.GotDnmSnapshot();
  }

  function snapshotUvm(
    address[] memory addresses,
    uint256[] memory amounts
  ) public onlyOwner {
    BridgeLib.validateArrayLengths(
      addresses.length,
      amounts.length,
      "Address and amount length mismatch."
    );
    for (uint256 i = 0; i < addresses.length; i++) {
      uvmBalanceByAddressSnapshot[addresses[i]] = amounts[i];
    }
    emit BridgeLib.GotUvmSnapshot();
  }

  function snapshotWrapperToken(
    address[] memory addresses,
    uint256[][] memory tokenIds
  ) public onlyOwner {
    BridgeLib.validateArrayLengths(
      addresses.length,
      tokenIds.length,
      "Address and tokenId length mismatch."
    );
    for (uint256 i = 0; i < addresses.length; i++) {
      wrapperTokenIdsByAddressSnapshot[addresses[i]] = tokenIds[i];
    }
    emit BridgeLib.GotWrapperSnapshot();
  }

  // function snapshotArusanseToken(
  //   address[] memory addresses,
  //   uint256[][] memory tokenIds
  // ) public onlyOwner {
  //   BridgeLib.validateArrayLengths(
  //     addresses.length,
  //     tokenIds.length,
  //     "Address and tokenId length mismatch."
  //   );
  //   for (uint256 i = 0; i < addresses.length; i++) {
  //     arusenseTokenIdsByAddressSnapshot[addresses[i]] = tokenIds[i];
  //   }
  //   emit BridgeLib.GotWrapperSnapshot();
  // }

  function snapshotStake(
    uint256[] memory stakeIds,
    BridgeLib.Stake[] memory stakes
  ) public onlyOwner {
    BridgeLib.validateArrayLengths(
      stakeIds.length,
      stakes.length,
      "Address and tokenId length mismatch."
    );
    for (uint256 i = 0; i < stakeIds.length; i++) {
      stakeSnapshot[stakeIds[i]] = stakes[i];
    }
    emit BridgeLib.GotStakeSnapshot();
  }

  function withdrawDnm(uint256 amount) public onlyOwner {
    uint256 dnmBalance = BridgeLib.getERC20Balance(
      oldDnmAddress,
      address(this)
    );
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
    emit BridgeLib.DnmWithdrawnByOwner(amount);
  }

  function withdrawRemainingNewDnm() public onlyOwner {
    uint256 contractBalance = BridgeLib.getERC20Balance(
      newDnmAddress,
      address(this)
    );
    BridgeLib.transferERC20From(
      newDnmAddress,
      address(this),
      msg.sender,
      contractBalance,
      "DNM transfer from contract to user wasn't successful."
    );
    emit BridgeLib.RemainingNewDnmWithdrawnByOwner(contractBalance);
  }

  function withdrawUvm(uint256 amount) public onlyOwner {
    uint256 uvmBalance = BridgeLib.getERC20Balance(
      oldUvmAddress,
      address(this)
    );
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
    emit BridgeLib.UvmWithdrawnByOwner(amount);
  }

  // function withdrawArusenseToken(uint256 tokenId) public onlyOwner {
  //   IERC721 arusenseContract = IERC721(oldArusenseAddress);
  //   arusenseContract.transferFrom(address(this), msg.sender, tokenId);
  //   emit BridgeLib.ArusenseTokenWithdrawnByOwner(tokenId);
  // }

  function withdrawWrapperToken(uint256 tokenId) public onlyOwner {
    IWrapper wrapperTokenContract = IWrapper(oldWrapperTokenAddress);
    wrapperTokenContract.transferFrom(address(this), msg.sender, tokenId);
    emit BridgeLib.WrapperTokenWithdrawnByOwner(tokenId);
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
    uvmBalanceByAddressSnapshot[msg.sender] -= bridgedBalance;

    uint256 dnmAmount = BridgeLib.calculateDnmFromUvm(bridgedBalance);
    BridgeLib.transferERC20From(
      newDnmAddress,
      address(this),
      msg.sender,
      dnmAmount,
      "DNM transfer from contract to user wasn't successful."
    );
    emit BridgeLib.UvmBridgedByUser(msg.sender, bridgedBalance, dnmAmount);
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
    dnmBalanceByAddressSnapshot[msg.sender] -= bridgedBalance;

    uint256 dnmAmount = BridgeLib.calculateNewDnmFromOldDnm(bridgedBalance);
    BridgeLib.transferERC20From(
      newDnmAddress,
      address(this),
      msg.sender,
      dnmAmount,
      "DNM transfer from contract to user wasn't successful."
    );
    emit BridgeLib.DnmBridgedByUser(msg.sender, bridgedBalance, bridgedBalance);
  }

  // function bridgeArusenseNFT(uint256 tokenId) public inDeadlineDuration {
  //   uint256[] memory tokenIds = arusenseTokenIdsByAddressSnapshot[msg.sender];
  //   require(
  //     BridgeLib.validateTokenExistsInArray(tokenId, tokenIds),
  //     "Token doesn't exist in the snapshot."
  //   );

  //   BridgeLib.validateTokenOwnership(oldArusenseAddress, tokenId, msg.sender);

  //   INFTLandMarket arusenseMarketContract = INFTLandMarket(
  //     oldArusenseMarketAddress
  //   );
  //   (uint256 bv, uint256 sv) = arusenseMarketContract.getMintPrice(tokenId);
  //   IERC721(oldArusenseAddress).safeTransferFrom(
  //     msg.sender,
  //     address(this),
  //     tokenId
  //   );

  //   uint256 dnmAmount = BridgeLib.calculateDnmFromPrices(bv, sv);
  //   BridgeLib.transferERC20From(
  //     newDnmAddress,
  //     address(this),
  //     msg.sender,
  //     dnmAmount,
  //     "DNM transfer from contract to user wasn't successful."
  //   );

  //   arusenseTokenIds.push(tokenId);
  //   emit BridgeLib.ArusenseTokenBridgedByUser(msg.sender, tokenId, dnmAmount);
  // }

  function bridgeWrapperToken(uint256 tokenId) public inDeadlineDuration {
    IWrapper wrapperTokenContract = IWrapper(oldWrapperTokenAddress);
    uint256[] memory tokenIds = wrapperTokenIdsByAddressSnapshot[msg.sender];
    require(
      BridgeLib.validateTokenExistsInArray(tokenId, tokenIds),
      "Token doesn't exist in the snapshot."
    );

    BridgeLib.validateTokenOwnership(
      oldWrapperTokenAddress,
      tokenId,
      msg.sender
    );

    uint256 uvmAmount = BridgeLib.getUvmAmountByWrapperTokenType(
      wrapperTokenContract.getWrapTokenPlan(tokenId)
    );
    uint256 dnmAmount = BridgeLib.calculateDnmFromUvm(uvmAmount);
    wrapperTokenContract.safeTransferFrom(msg.sender, address(this), tokenId);

    BridgeLib.transferERC20From(
      newDnmAddress,
      address(this),
      msg.sender,
      dnmAmount,
      "DNM transfer from contract to user wasn't successful."
    );

    wrapperTokenIds.push(tokenId);
    emit BridgeLib.WrapperTokenBridgedByUser(msg.sender, tokenId, dnmAmount);
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
    uint256 totalDnmAmount = BridgeLib.calculateDnmFromUvm(stakePlan.uvm);

    BridgeLib.transferERC20From(
      oldDnmAddress,
      stake.userAddress,
      address(this),
      stakePlan.dnm,
      "Previous DNM transfer from user to contract wasn't successful."
    );
    totalDnmAmount += BridgeLib.calculateNewDnmFromOldDnm(stakePlan.dnm);

    IWrapper wrapperTokenContract = IWrapper(oldWrapperTokenAddress);
    uint256 uvmAmount = BridgeLib.getUvmAmountByWrapperTokenType(
      wrapperTokenContract.getWrapTokenPlan(stakePlan.land)
    );
    totalDnmAmount += BridgeLib.calculateDnmFromUvm(uvmAmount);
    wrapperTokenContract.safeTransferFrom(
      msg.sender,
      address(this),
      stakePlan.land
    );

    wrapperTokenIds.push(stakePlan.land);

    BridgeLib.transferERC20From(
      newDnmAddress,
      address(this),
      msg.sender,
      totalDnmAmount,
      "New DNM transfer from contract to user wasn't successful."
    );

    stakeSnapshot[stakeId].principleWithdrawn = true;
    emit BridgeLib.StakePrincipleBridgedByUser(
      msg.sender,
      stakeId,
      stakePlan.uvm,
      stakePlan.dnm,
      stakePlan.land,
      totalDnmAmount
    );
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

    stake.totalPaidOut += uvmAmount;

    uint256 dnmAmount = BridgeLib.calculateDnmFromUvm(uvmAmount);
    BridgeLib.transferERC20From(
      newDnmAddress,
      address(this),
      msg.sender,
      dnmAmount,
      "New DNM transfer from contract to user wasn't successful."
    );

    emit BridgeLib.StakeYieldBridgedByUser(
      msg.sender,
      stakeId,
      uvmAmount,
      dnmAmount
    );
  }
}
