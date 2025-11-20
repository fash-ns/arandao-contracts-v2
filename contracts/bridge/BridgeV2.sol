// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

import {IWrapper} from "./IWrapper.sol";
import {IStakeMeta} from "./IStakeMeta.sol";
import {BridgeLib} from "./BridgeLib.sol";
import {ERC721Holder} from "@openzeppelin/contracts/token/ERC721/utils/ERC721Holder.sol";

import {Initializable} from "@openzeppelin/contracts/proxy/utils/Initializable.sol";
import {OwnableUpgradeable} from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import {UUPSUpgradeable} from "@openzeppelin/contracts/proxy/utils/UUPSUpgradeable.sol";

contract AranDAOBridgeV2 is
  ERC721Holder,
  Initializable,
  OwnableUpgradeable,
  UUPSUpgradeable
{
  address public oldUvmAddress;
  address public oldDnmAddress;
  address public oldWrapperTokenAddress;
  address public oldStakeAddress;
  address public arcAddress;
  uint256 public constructionTime;
  uint256 upgradeDeadline;

  uint256[] public wrapperTokenIds;

  bool private canSubmitSnapshot;
  mapping(address => uint256) public uvmBalanceByAddressSnapshot;
  mapping(address => uint256) public dnmBalanceByAddressSnapshot;
  mapping(address => uint256[]) public wrapperTokenIdsByAddressSnapshot;
  mapping(uint256 => BridgeLib.Stake) public stakeSnapshot;

  modifier inDeadlineDuration() {
    BridgeLib.validateDeadline(constructionTime);
    _;
  }

  /// @custom:oz-upgrades-unsafe-allow constructor
  constructor() {
    _disableInitializers();
  }

  modifier inUpgradeTime() {
    require(
      upgradeDeadline >= block.timestamp,
      "The upgrade allowed time has been passed."
    );
    _;
  }

  function initialize(
    address initialOwner,
    address _oldUvmAddress,
    address _oldDnmAddress,
    address _oldWrapperTokenAddress,
    address _oldStakeAddress,
    address _arcAddress
  ) public initializer {
    __Ownable_init(initialOwner);

    oldUvmAddress = _oldUvmAddress;
    oldDnmAddress = _oldDnmAddress;
    oldWrapperTokenAddress = _oldWrapperTokenAddress;
    oldStakeAddress = _oldStakeAddress;
    arcAddress = _arcAddress;
    constructionTime = block.timestamp;

    canSubmitSnapshot = true;
    upgradeDeadline = block.timestamp + 90 days;
  }

  function extendUpgradableDeadline() public inUpgradeTime onlyOwner {
    upgradeDeadline = block.timestamp + 90 days;
  }

  function _authorizeUpgrade(
    address newImplementation
  ) internal override onlyOwner inUpgradeTime {}

  function finishSnapshotTaking() public onlyOwner {
    canSubmitSnapshot = false;
  }

  function snapshotDnm(
    address[] memory addresses,
    uint256[] memory amounts
  ) public onlyOwner {
    if (true) {
      revert("Not supported in V2");
    }
    BridgeLib.validateArrayLengths(
      addresses.length,
      amounts.length,
      "Address and amount length mismatch."
    );
    require(canSubmitSnapshot, "Submit snapshot is no more possible");

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
    require(canSubmitSnapshot, "Submit snapshot is no more possible");

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
    require(canSubmitSnapshot, "Submit snapshot is no more possible");
    for (uint256 i = 0; i < addresses.length; i++) {
      wrapperTokenIdsByAddressSnapshot[addresses[i]] = tokenIds[i];
    }
    emit BridgeLib.GotWrapperSnapshot();
  }

  function snapshotStake(
    uint256[] memory stakeIds,
    BridgeLib.Stake[] memory stakes
  ) public onlyOwner {
    BridgeLib.validateArrayLengths(
      stakeIds.length,
      stakes.length,
      "Address and tokenId length mismatch."
    );
    require(canSubmitSnapshot, "Submit snapshot is no more possible");
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
    emit BridgeLib.DnmWithdrawnByOwner(amount);
  }

  function withdrawRemainingArc(uint256 amount) public onlyOwner {
    uint256 contractBalance = BridgeLib.getERC20Balance(
      arcAddress,
      address(this)
    );
    require(
      amount <= contractBalance,
      "Amount is greater than the contract's ARC balance."
    );

    BridgeLib.transferERC20From(
      arcAddress,
      address(this),
      msg.sender,
      amount,
      "ARC transfer from contract to user wasn't successful."
    );
    emit BridgeLib.RemainingArcWithdrawnByOwner(amount);
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
    emit BridgeLib.UvmWithdrawnByOwner(amount);
  }

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

    uvmBalanceByAddressSnapshot[msg.sender] -= bridgedBalance;

    BridgeLib.transferERC20From(
      oldUvmAddress,
      msg.sender,
      address(this),
      bridgedBalance,
      "UVM transfer from user to contract wasn't successful."
    );

    uint256 dnmAmount = BridgeLib.calculateDnmFromUvm(bridgedBalance);
    BridgeLib.transferERC20From(
      arcAddress,
      address(this),
      msg.sender,
      dnmAmount,
      "ARC transfer from contract to user wasn't successful."
    );
    emit BridgeLib.UvmBridgedByUser(msg.sender, bridgedBalance, dnmAmount);
  }

  function bridgeDnm() public inDeadlineDuration {
    uint256 userBalance = BridgeLib.getERC20Balance(oldDnmAddress, msg.sender);
    uint256 bridgedBalance = BridgeLib.validateBridgeAmount(
      dnmBalanceByAddressSnapshot[msg.sender],
      userBalance
    );

    dnmBalanceByAddressSnapshot[msg.sender] -= bridgedBalance;

    BridgeLib.transferERC20From(
      oldDnmAddress,
      msg.sender,
      address(this),
      bridgedBalance,
      "DNM transfer from user to contract wasn't successful."
    );

    uint256 dnmAmount = BridgeLib.calculateNewDnmFromOldDnm(bridgedBalance);
    BridgeLib.transferERC20From(
      arcAddress,
      address(this),
      msg.sender,
      dnmAmount,
      "ARC transfer from contract to user wasn't successful."
    );
    emit BridgeLib.DnmBridgedByUser(msg.sender, bridgedBalance, bridgedBalance);
  }

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

    wrapperTokenIds.push(tokenId);

    wrapperTokenContract.safeTransferFrom(msg.sender, address(this), tokenId);

    BridgeLib.transferERC20From(
      arcAddress,
      address(this),
      msg.sender,
      dnmAmount,
      "ARC transfer from contract to user wasn't successful."
    );

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
      90
    );
    require(
      block.timestamp <= eligibleTimestamp,
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

    stakeSnapshot[stakeId].principleWithdrawn = true;

    BridgeLib.transferERC20From(
      arcAddress,
      address(this),
      msg.sender,
      totalDnmAmount,
      "ARC transfer from contract to user wasn't successful."
    );

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

    IStakeMeta stakeContract = IStakeMeta(oldStakeAddress);
    IStakeMeta.StakePlan memory stakePlan = stakeContract.getStake(stakeId);

    BridgeLib.validateStakeClosed(stakePlan.finish);

    uint256 eligibleTimestamp = BridgeLib.calculateEligibilityTimestamp(
      stakePlan.finish,
      300 days,
      constructionTime,
      90
    );

    require(
      block.timestamp <= eligibleTimestamp,
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

    stake.totalPaidOut += uvmAmount;

    BridgeLib.transferERC20From(
      oldUvmAddress,
      stake.userAddress,
      address(this),
      uvmAmount,
      "UVM transfer from user to contract wasn't successful."
    );

    uint256 dnmAmount = BridgeLib.calculateDnmFromUvm(uvmAmount);

    BridgeLib.transferERC20From(
      arcAddress,
      address(this),
      msg.sender,
      dnmAmount,
      "ARC transfer from contract to user wasn't successful."
    );

    emit BridgeLib.StakeYieldBridgedByUser(
      msg.sender,
      stakeId,
      uvmAmount,
      dnmAmount
    );
  }

  function version() public pure returns (uint8) {
    return 2;
  }
}
