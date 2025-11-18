// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

import {IERC721Enumerable} from "@openzeppelin/contracts/token/ERC721/extensions/IERC721Enumerable.sol";

interface IWrapper is IERC721Enumerable {
    struct Collection {
        uint256 type_count;
        bool mint_status;
        bool withdraw_status;
        bool exists;
    }

    struct PlanType {
        uint256 start;
        uint256 end;
        uint8 plan;
    }

    struct WrapToken {
        address collection_address;
        uint256 token_id;
        uint8 plan_type;
        bool burned;
    }

    function wrapTokenList(uint256) external view returns (WrapToken memory);
    function changeDao(address _dao) external;
    function addOrUpdateCollection(
        address _collection,
        Collection memory collectData,
        PlanType[] memory planTypes
    ) external;
    function changeCollectionStatus(
        address _collection,
        bool mint_status,
        bool withdraw_status
    ) external;
    function getUserTokens(
        address user
    ) external view returns (uint256[] memory);
    function getUserTokensInfo() external view returns (WrapToken[] memory);
    function getUserTokensInfo(
        address user
    ) external view returns (WrapToken[] memory);
    function getTokenPlan(
        address _collection,
        uint256 id
    ) external view returns (uint8);
    function getWrapTokenPlan(uint256 id) external view returns (uint8);
    function mint(
        address _collection,
        address to,
        uint256 id
    ) external returns (uint256);
    function withdraw(address _collection, uint256 wrapTokenId) external;
}
