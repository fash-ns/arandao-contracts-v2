// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

interface IStakeMeta {
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

    struct User {
        uint256 id;
        bool exists;
        uint256[] stakePlanIds;
        uint256 totalReward;
    }

    function userList(uint256) external view returns (address);
    function stakeFrom(
        address staker,
        uint256 dnmAmount,
        uint256 wrapper_id,
        uint256 stake_duration
    ) external;
    function stake(
        uint256 dnmAmount,
        uint256 land_id,
        uint256 stake_duration
    ) external;
    function withdrawStake(uint256 stake_id, bool withdraw_reward) external;
    function setFeePercent(uint256 _fee_percent) external;
    function withdrawReward(uint256 stake_id) external returns (bool);
    function withdrawFeeByDao(uint256 amount, address to) external;
    function getUserStakeIds(
        address user_address
    ) external view returns (uint256[] memory);
    function getUserStake(
        address user_address
    ) external view returns (StakePlan[] memory);
    function getAllStake() external view returns (StakePlan[] memory);
    function getActiveStake() external view returns (StakePlan[] memory);
    function getFinishedStake() external view returns (StakePlan[] memory);
    function getStake(uint256 id) external view returns (StakePlan memory sp);
    function getPlanByTokenId(uint256 land_id) external view returns (uint8);
    function getContractUVMBalance() external view returns (uint256);
    function getContractDNMBalance() external view returns (uint256);
    function getUser(
        address user_address
    ) external view returns (uint256, bool, uint256);
    function calDnmUvmRatio(uint256 dnm) external pure returns (uint256);
    function allowedDnmAmountStake(uint8 plan) external view returns (uint256);
    function calculateRewardForStake(
        uint256 stake_id
    ) external view returns (uint256);
    function withdrawAllowance(
        StakePlan memory sp
    ) external view returns (uint256);
    function calculateReward(
        uint16 plan_type,
        uint256 dnm_amount,
        uint256 start,
        uint256 end,
        uint256 stake_duration
    ) external view returns (uint256);
    function addTokenToPool(uint256 amount) external;
    function setDao(address _dao) external;
}
