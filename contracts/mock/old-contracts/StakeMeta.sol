// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {IERC721} from "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
// import {TopUp} from "./stake_helpers/TopUp.sol";
import {LandPlan} from "./LandPlan.sol";

interface IWrapper is IERC721 {
  function getWrapTokenPlan(uint256 id) external view returns (uint8);
}

contract StakeMeta is Ownable, LandPlan {
  address public dao;

  ERC20 public UVM_TOKEN;
  ERC20 public DNM_TOKEN;
  IWrapper public WRAPPER_TOKEN;

  uint256 public constant TIME_STEP = 1 hours;
  uint256 public constant REWARD_DECAY_FACTOR = 20;
  uint256 public constant REWARD_DECAY_PERIOD = 12 hours;
  uint256 public constant STAKE_MAX_DNM = 28 ether;
  uint256 public constant STAKE_MIN_DNM = 1 ether;
  uint256 public constant STAKE_MAX_UVM = 6000 ether;

  uint256 public LAUNCH_TIME;
  uint256 public TOTAL_UVM_STAKED;
  uint256 public TOTAL_DNM_STAKED;
  uint256 public TOTAL_LAND_STAKED;
  uint256 public TOTAL_REWARD;
  uint256 public UVM_POOL_BALANCE = 0;
  uint256 public UVM_FEE_BALANCE = 0;
  uint256 public STAKE_LIST_ID = 0;
  uint256 public USER_LIST_ID = 0;
  uint256 public FEE_PERCENT = 0.01 ether;

  //STAKE DURATIONS
  uint256 public constant ONE_YEAR_DURATION = 12 hours;
  uint256 public constant EIGHTEEN_MONTH_DURATION = 18 hours;
  uint256 public constant TWO_YEAR_DURATION = 24 hours;

  struct StakePlan {
    uint256 userId;
    bool exists;
    uint8 plan;
    uint256 uvm;
    uint256 dnm;
    uint256 land;
    uint256 start;
    uint256 finish;
    uint256 stake_duration;
    uint256 total_paid_out;
  }

  mapping(uint16 => uint256) internal planDnmAllowed;

  struct User {
    uint256 id;
    bool exists;
    uint256[] stakePlanIds;
    uint256 totalReward;
  }

  mapping(address => User) internal users;
  mapping(uint256 => address) public userList;
  mapping(uint256 => StakePlan) public stakeList;

  constructor(
    address uvm_token,
    address dnm_token,
    address land_token_wrapper,
    uint256 launch_time
  ) Ownable(msg.sender) {
    LAUNCH_TIME = launch_time;
    UVM_TOKEN = ERC20(uvm_token);
    DNM_TOKEN = ERC20(dnm_token);
    WRAPPER_TOKEN = IWrapper(land_token_wrapper);
    planDnmAllowed[1] = 280e17;
    planDnmAllowed[2] = 140e17;
    planDnmAllowed[3] = 70e17;
    planDnmAllowed[4] = 28e17;
    planDnmAllowed[5] = 14e17;
  }

  //------------------------------------------ Stake ------------------------------------------

  function stakeFrom(
    address staker,
    uint256 dnmAmount,
    uint256 wrapper_id,
    uint256 stake_duration
  ) public {
    require(
      stake_duration == ONE_YEAR_DURATION ||
        stake_duration == EIGHTEEN_MONTH_DURATION ||
        stake_duration == TWO_YEAR_DURATION,
      "Invalid stake time"
    );
    uint8 plan = getPlanByTokenId(wrapper_id);
    require(plan < 6 && plan > 0, "Invalid plan");
    uint256 max_dnm_allowed = allowedDnmAmountStake(plan);
    require(
      dnmAmount <= max_dnm_allowed && dnmAmount >= STAKE_MIN_DNM,
      "DNM amount is not in correct range"
    );
    uint256 uvmAmount = calDnmUvmRatio(dnmAmount);
    require(
      DNM_TOKEN.balanceOf(msg.sender) >= dnmAmount,
      "DNM balance is not enough"
    );
    require(
      UVM_TOKEN.balanceOf(msg.sender) >= uvmAmount,
      "UVM balance is not enough"
    );
    require(
      WRAPPER_TOKEN.ownerOf(wrapper_id) == msg.sender,
      "You are not owner of land"
    );

    bool d_transfer = DNM_TOKEN.transferFrom(
      msg.sender,
      address(this),
      dnmAmount
    );

    require(d_transfer == true, "Internal Error On DNM Transfer");
    TOTAL_DNM_STAKED = TOTAL_DNM_STAKED + dnmAmount;

    bool u_transfer = UVM_TOKEN.transferFrom(
      msg.sender,
      address(this),
      uvmAmount
    );
    require(u_transfer == true, "Internal Error On Uvm Transfer");
    TOTAL_UVM_STAKED = TOTAL_UVM_STAKED + uvmAmount;

    WRAPPER_TOKEN.transferFrom(msg.sender, address(this), wrapper_id);
    TOTAL_LAND_STAKED = TOTAL_LAND_STAKED + 1;

    User memory user = users[staker];

    if (user.exists == false) {
      USER_LIST_ID++;

      user = User({
        id: USER_LIST_ID,
        exists: true,
        stakePlanIds: new uint256[](0),
        totalReward: 0
      });

      userList[USER_LIST_ID] = staker;
      emit NewUser(staker, USER_LIST_ID);
    }

    StakePlan memory sp = StakePlan({
      userId: user.id,
      exists: true,
      plan: plan,
      uvm: uvmAmount,
      dnm: dnmAmount,
      land: wrapper_id,
      start: block.timestamp,
      finish: 0,
      stake_duration: stake_duration,
      total_paid_out: 0
    });

    STAKE_LIST_ID++;
    stakeList[STAKE_LIST_ID] = sp;
    users[staker] = user;
    users[staker].stakePlanIds.push(STAKE_LIST_ID);

    emit NewStake(
      user.id,
      plan,
      dnmAmount,
      uvmAmount,
      wrapper_id,
      STAKE_LIST_ID
    );
  }

  function stake(
    uint256 dnmAmount,
    uint256 land_id,
    uint256 stake_duration
  ) public {
    require(
      stake_duration == ONE_YEAR_DURATION ||
        stake_duration == EIGHTEEN_MONTH_DURATION ||
        stake_duration == TWO_YEAR_DURATION,
      "Invalid stake time"
    );
    uint8 plan = getPlanByTokenId(land_id);
    require(plan < 6 && plan > 0, "Invalid plan");
    uint256 max_dnm_allowed = allowedDnmAmountStake(plan);
    require(
      dnmAmount <= max_dnm_allowed && dnmAmount >= STAKE_MIN_DNM,
      "DNM amount is not in correct range"
    );

    uint256 uvmAmount = calDnmUvmRatio(dnmAmount);
    require(
      DNM_TOKEN.balanceOf(msg.sender) >= dnmAmount,
      "DNM balance is not enough"
    );
    require(
      UVM_TOKEN.balanceOf(msg.sender) >= uvmAmount,
      "UVM balance is not enough"
    );
    require(
      WRAPPER_TOKEN.ownerOf(land_id) == msg.sender,
      "You are not owner of land"
    );

    bool d_transfer = DNM_TOKEN.transferFrom(
      msg.sender,
      address(this),
      dnmAmount
    );
    require(d_transfer == true, "Internal Error On DNM Transfer");
    TOTAL_DNM_STAKED = TOTAL_DNM_STAKED + dnmAmount;
    bool u_transfer = UVM_TOKEN.transferFrom(
      msg.sender,
      address(this),
      uvmAmount
    );
    require(u_transfer == true, "Internal Error On Uvm Transfer");
    TOTAL_UVM_STAKED = TOTAL_UVM_STAKED + uvmAmount;

    WRAPPER_TOKEN.transferFrom(msg.sender, address(this), land_id);
    TOTAL_LAND_STAKED = TOTAL_LAND_STAKED + 1;

    User memory user = users[msg.sender];

    if (user.exists == false) {
      USER_LIST_ID++;

      user = User({
        id: USER_LIST_ID,
        exists: true,
        stakePlanIds: new uint256[](0),
        totalReward: 0
      });

      userList[USER_LIST_ID] = msg.sender;
      emit NewUser(msg.sender, USER_LIST_ID);
    }

    StakePlan memory sp = StakePlan({
      userId: user.id,
      exists: true,
      plan: plan,
      uvm: uvmAmount,
      dnm: dnmAmount,
      land: land_id,
      start: block.timestamp,
      finish: 0,
      stake_duration: stake_duration,
      total_paid_out: 0
    });

    STAKE_LIST_ID++;
    stakeList[STAKE_LIST_ID] = sp;
    users[msg.sender] = user;
    users[msg.sender].stakePlanIds.push(STAKE_LIST_ID);

    emit NewStake(user.id, plan, dnmAmount, uvmAmount, land_id, STAKE_LIST_ID);
  }

  //------------------------------------------ Withdraws ------------------------------------------

  function withdrawStake(uint256 stake_id, bool withdraw_reward) public {
    User storage user = users[msg.sender];
    StakePlan memory sp = stakeList[stake_id];

    require(user.exists == true, "user does not exist");
    require(sp.exists == true, "stake is not exists");
    require(sp.finish == 0, "stake is not active");
    require(sp.userId == user.id, "you can only withdraw your reward");

    require(
      (block.timestamp - sp.start) > sp.stake_duration,
      "You should wait at least a year"
    );

    // finish stake and save
    sp.finish = block.timestamp;
    stakeList[stake_id] = sp;

    // send user token from stake
    UVM_TOKEN.transfer(msg.sender, sp.uvm);
    TOTAL_UVM_STAKED = TOTAL_UVM_STAKED - sp.uvm;

    DNM_TOKEN.transfer(msg.sender, sp.dnm);
    TOTAL_DNM_STAKED = TOTAL_DNM_STAKED - sp.dnm;

    WRAPPER_TOKEN.transferFrom(address(this), msg.sender, sp.land);
    TOTAL_LAND_STAKED = TOTAL_LAND_STAKED - 1;

    // check if withdraw reward and call function
    if (withdraw_reward == true) {
      withdrawReward(stake_id);
    }

    // emit events
    emit WithdrawUserStake(stake_id);
  }

  function setFeePercent(uint256 _fee_percent) public onlyDao {
    require(
      _fee_percent >= 0.01 ether && _fee_percent <= 0.1 ether,
      "fee percent"
    );
    FEE_PERCENT = _fee_percent;
  }

  function withdrawReward(uint256 stake_id) public returns (bool) {
    User storage user = users[msg.sender];
    StakePlan memory sp = stakeList[stake_id];
    require(user.exists == true, "user does not exist");
    require(sp.exists == true, "stake is not exists");
    require(sp.userId == user.id, "you can only withdraw your reward");

    require(
      (block.timestamp - sp.start) > sp.stake_duration,
      "You should wait at least a year"
    );

    uint256 reward_amount = calculateRewardForStake(stake_id);

    require(UVM_POOL_BALANCE >= reward_amount, "Pool is empty");

    sp.total_paid_out += reward_amount;
    user.totalReward += reward_amount;
    // deducts 1% fee
    uint256 user_reward_amount = reward_amount -
      ((reward_amount * FEE_PERCENT) / 1e18);

    uint256 fee = reward_amount - user_reward_amount;

    if (user_reward_amount > 0) {
      UVM_POOL_BALANCE = UVM_POOL_BALANCE - reward_amount;
      stakeList[stake_id] = sp;
      transferReward(msg.sender, user_reward_amount);
      UVM_FEE_BALANCE += fee;
      emit Withdraw(msg.sender, user_reward_amount);
      return true;
    }

    return false;
  }

  function withdrawFeeByDao(uint256 amount, address to) public onlyDao {
    require(amount <= UVM_FEE_BALANCE, "amount is not correct");
    UVM_FEE_BALANCE -= amount;
    UVM_TOKEN.transfer(to, amount);
  }

  //------------------------------------------ Getters ------------------------------------------
  function getUserStakeIds(
    address user_address
  ) public view returns (uint256[] memory) {
    return users[user_address].stakePlanIds;
  }

  function getUserStake(
    address user_address
  ) public view returns (StakePlan[] memory) {
    uint256 spLength = users[user_address].stakePlanIds.length;
    StakePlan[] memory StakePlanArray = new StakePlan[](spLength);
    for (uint256 i = 0; i < spLength; i++) {
      StakePlanArray[i] = stakeList[users[user_address].stakePlanIds[i]];
    }
    return StakePlanArray;
  }

  function getAllStake() public view returns (StakePlan[] memory) {
    StakePlan[] memory StakePlanArray = new StakePlan[](STAKE_LIST_ID);

    for (uint256 i = 1; i <= STAKE_LIST_ID; i++) {
      StakePlanArray[(i - 1)] = stakeList[i];
    }

    return StakePlanArray;
  }

  function getActiveStake() public view returns (StakePlan[] memory) {
    StakePlan[] memory StakePlanArray = new StakePlan[](TOTAL_LAND_STAKED);

    uint256 _i = 0;
    for (uint256 i = 1; i <= STAKE_LIST_ID; i++) {
      if (stakeList[i].finish == 0) {
        StakePlanArray[_i] = stakeList[i];
        _i = _i + 1;
      }
    }

    return StakePlanArray;
  }

  function getFinishedStake() public view returns (StakePlan[] memory) {
    uint256 count = (STAKE_LIST_ID - TOTAL_LAND_STAKED);
    StakePlan[] memory StakePlanArray = new StakePlan[](count);

    uint256 _i = 0;
    for (uint256 i = 1; i <= count; i++) {
      if (stakeList[i].finish > 0) {
        StakePlanArray[_i] = stakeList[i];
        _i = _i + 1;
      }
    }

    return StakePlanArray;
  }

  function getStake(uint256 id) public view returns (StakePlan memory sp) {
    return stakeList[id];
  }

  function getPlanByTokenId(uint256 land_id) public view returns (uint8) {
    return WRAPPER_TOKEN.getWrapTokenPlan(land_id);
  }

  function getContractUVMBalance() public view returns (uint256) {
    return UVM_TOKEN.balanceOf(address(this));
  }

  function getContractDNMBalance() public view returns (uint256) {
    return DNM_TOKEN.balanceOf(address(this));
  }

  function getUser(
    address user_address
  ) public view returns (uint256, bool, uint256) {
    return (
      users[user_address].id,
      users[user_address].exists,
      users[user_address].totalReward
    );
  }

  //------------------------------------------ Reward Calculators ------------------------------------------

  function calDnmUvmRatio(uint256 dnm) public pure returns (uint256) {
    return (STAKE_MAX_UVM * dnm) / STAKE_MAX_DNM;
  }

  function allowedDnmAmountStake(uint8 plan) public view returns (uint256) {
    return planDnmAllowed[plan];
  }

  function calculateRewardForStake(
    uint256 stake_id
  ) public view returns (uint256) {
    require(stakeList[stake_id].exists == true, "stake is not exists");
    StakePlan memory sp = stakeList[stake_id];
    if (sp.finish > 0) {
      return withdrawAllowance(sp);
    } else {
      sp.finish = block.timestamp;
      return withdrawAllowance(sp);
    }
  }

  function withdrawAllowance(
    StakePlan memory sp
  ) public view returns (uint256) {
    uint256 full_reward = calculateReward(
      sp.plan,
      sp.dnm,
      sp.start,
      sp.finish,
      sp.stake_duration
    );

    uint256 withdrawal_amount = full_reward - sp.total_paid_out;

    require(withdrawal_amount > 0, "you have withdrawn all of the full reward");

    require(
      (block.timestamp - sp.start) > sp.stake_duration,
      "it is before stake duration"
    );

    uint256 past_of_stake_duration = (block.timestamp - sp.start) -
      sp.stake_duration;

    past_of_stake_duration = (past_of_stake_duration / 30 days) + 1;

    if (past_of_stake_duration >= 10) {
      past_of_stake_duration = 10;
    }
    uint256 available = (full_reward / 10) * past_of_stake_duration;

    withdrawal_amount = available - sp.total_paid_out;
    require(
      withdrawal_amount > 0,
      "you have withdrawn all of the monthly reward"
    );

    return withdrawal_amount;
  }

  function calculateReward(
    uint16 plan_type,
    uint256 dnm_amount,
    uint256 start,
    uint256 end,
    uint256 stake_duration
  ) public view returns (uint256) {
    require(plan_type < 6 && plan_type > 0, "Invalid plan");
    require(dnm_amount > 0, "Invalid dnm amount");
    require(start <= end, "Invalid start and end");

    uint256 elapsedStep = (end - start) / TIME_STEP;
    uint256 totalReward = 0;

    for (uint256 i = 1; i <= elapsedStep; i++) {
      //represents the number of years that have passed since the staking began.
      uint256 years_passed = (((start + ((i - 1) * TIME_STEP)) - LAUNCH_TIME)) /
        REWARD_DECAY_PERIOD;

      uint256 reward_uvm_land;
      uint256 reward_uvm_dnm;
      if (stake_duration == ONE_YEAR_DURATION) {
        (reward_uvm_land, reward_uvm_dnm) = calculateByPlan(
          plans_12[plan_type],
          dnm_amount
        );
      }

      if (stake_duration == EIGHTEEN_MONTH_DURATION) {
        (reward_uvm_land, reward_uvm_dnm) = calculateByPlan(
          plans_18[plan_type],
          dnm_amount
        );
      }

      if (stake_duration == TWO_YEAR_DURATION) {
        (reward_uvm_land, reward_uvm_dnm) = calculateByPlan(
          plans_24[plan_type],
          dnm_amount
        );
      }
      uint256 temp_reward = reward_uvm_land + reward_uvm_dnm;
      //reduce 20% of reward for each year that has passed
      for (uint256 j = 0; j < years_passed; j++) {
        temp_reward = (temp_reward * (100 - REWARD_DECAY_FACTOR)) / 100;
      }
      totalReward = totalReward + temp_reward;
    }
    return totalReward;
  }

  function calculateByPlan(
    Plan storage plan,
    uint256 dnm_amount
  ) internal view returns (uint256, uint256) {
    return (plan.uvmPerLand, (plan.uvmPerDnm * dnm_amount) / 1e18);
  }

  function addTokenToPool(uint256 amount) public {
    require(
      UVM_TOKEN.balanceOf(msg.sender) >= amount,
      "UVM balance is not enough"
    );
    bool u_transfer = UVM_TOKEN.transferFrom(msg.sender, address(this), amount);
    require(u_transfer == true, "Internal Error On Uvm Transfer !");
    UVM_POOL_BALANCE = UVM_POOL_BALANCE + amount;
    emit AddTokenToPool(msg.sender, amount);
  }

  function transferReward(address user_address, uint256 amount) private {
    TOTAL_REWARD = TOTAL_REWARD + amount;
    UVM_TOKEN.transfer(user_address, amount);
    emit TransferReward(user_address, amount);
  }

  modifier onlyDao() {
    if (msg.sender != dao) {
      revert OnlyDao();
    }
    _;
  }

  //------------------------------------------- Writes ----------------------------------------------
  function setDao(address _dao) public onlyOwner {
    if (dao != address(0)) {
      revert OnlyOnce();
    }
    dao = _dao;
  }

  //------------------------------------------- Events And Errors -----------------------------------------------
  error OnlyDao();
  error OnlyOnce();

  event NewUser(address indexed user_address, uint256 user_id);

  event NewStake(
    uint256 user_id,
    uint8 plan,
    uint256 dnmAmount,
    uint256 uvm_amount,
    uint256 land_id,
    uint256 stake_id
  );
  event WithdrawUserStake(uint256 stake_id);
  event Withdraw(address indexed user, uint256 amount);
  event TransferReward(address indexed to, uint256 amount);
  event AddTokenToPool(address indexed user, uint256 amount);
}
