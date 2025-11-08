// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import {ERC721Enumerable} from "@openzeppelin/contracts/token/ERC721/extensions/ERC721Enumerable.sol";
import {ERC721} from "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/Strings.sol";

contract Wrapper is ERC721Enumerable, Ownable {
  using Strings for uint256;

  error NotLandOwner();
  error NotWrapperOwner();
  error OnlyDao();

  string public baseURI;

  address public dao;

  modifier onlyDao() {
    _;
    // if (msg.sender != dao) {
    //     revert OnlyDao();
    // }
    // _;
  }

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

  function changeDao(address _dao) external onlyOwner {
    require(dao == address(0), "only once");
    dao = _dao;
  }

  mapping(address => Collection) public collections;
  mapping(address => mapping(uint256 => PlanType)) public collectionPlanTypes;
  mapping(uint256 => WrapToken) public wrapTokenList;
  uint256 public wrapTokenIndex = 0;

  constructor(
    string memory _baseURI
  ) ERC721("AranDao old wrapper token", "OldADN") Ownable(msg.sender) {
    baseURI = _baseURI;
  }

  modifier isCollectionExists(address _collection) {
    require(collections[_collection].exists, "collection is not exist");
    _;
  }

  modifier isLandOwner(address _collection, address to, uint256 tokenId) {
    if (ERC721(_collection).ownerOf(tokenId) != to) {
      revert NotLandOwner();
    }
    _;
  }

  function addOrUpdateCollection(
    address _collection,
    Collection memory collectData,
    PlanType[] memory planTypes
  ) public onlyDao {
    require(planTypes.length > 0, "plan types required");

    for (uint256 i; i < planTypes.length; i++) {
      require(
        planTypes[i].start < planTypes[i].end,
        "end must be greater than start"
      );

      require(
        planTypes[i].plan >= 1 && planTypes[i].plan <= 5,
        "plan is not correct"
      );

      collectionPlanTypes[_collection][i] = planTypes[i];
    }

    collectData.type_count = (planTypes.length - 1);
    collections[_collection] = collectData;
  }

  function changeCollectionStatus(
    address _collection,
    bool mint_status,
    bool withdraw_status
  ) public onlyDao isCollectionExists(_collection) {
    collections[_collection].mint_status = mint_status;
    collections[_collection].withdraw_status = withdraw_status;
  }

  function getUserTokens(address user) public view returns (uint256[] memory) {
    uint256 user_balance = balanceOf(user);
    uint256[] memory balance = new uint256[](user_balance);
    for (uint256 i; i < user_balance; i++) {
      balance[i] = tokenOfOwnerByIndex(user, i);
    }
    return balance;
  }

  function getUserTokensInfo() external view returns (WrapToken[] memory) {
    return getUserTokensInfo(msg.sender);
  }

  function getUserTokensInfo(
    address user
  ) public view returns (WrapToken[] memory) {
    uint256 user_balance = balanceOf(user);
    WrapToken[] memory balance = new WrapToken[](user_balance);
    for (uint256 i; i < user_balance; i++) {
      uint256 id = tokenOfOwnerByIndex(user, i);
      balance[i] = wrapTokenList[id];
    }
    return balance;
  }

  function getTokenPlan(
    address _collection,
    uint256 id
  ) public view returns (uint8) {
    for (uint256 i = 0; i <= collections[_collection].type_count; i++) {
      if (
        collectionPlanTypes[_collection][i].start <= id &&
        collectionPlanTypes[_collection][i].end >= id
      ) {
        return collectionPlanTypes[_collection][i].plan;
      }
    }

    return 0;
  }

  function getWrapTokenPlan(uint256 id) external view returns (uint8) {
    return wrapTokenList[id].plan_type;
  }

  function mint(
    uint8 planType,
    address to,
    uint256 id
  ) external returns (uint256) {
    // require(collections[_collection].mint_status, "mint is not enable !");

    // uint8 token_plan = getTokenPlan(_collection, id);
    // require(token_plan >= 1 && token_plan <= 5, "token plan is wrong !");

    wrapTokenList[wrapTokenIndex] = WrapToken({
      collection_address: 0x0000000000000000000000000000000000000000,
      token_id: id,
      plan_type: planType,
      burned: false
    });

    uint256 wrap_id = wrapTokenIndex;
    wrapTokenIndex++;

    _mint(to, wrap_id);

    // ERC721(_collection).transferFrom(to, address(this), id);

    return wrap_id;
  }

  function withdraw(
    address _collection,
    uint256 wrapTokenId
  ) public isCollectionExists(_collection) {
    require(
      collections[_collection].withdraw_status,
      "withdraw is not enable !"
    );
    if (ownerOf(wrapTokenId) != msg.sender) {
      revert NotWrapperOwner();
    }
    _burn(wrapTokenId);

    wrapTokenList[wrapTokenId].burned = true;

    ERC721(wrapTokenList[wrapTokenId].collection_address).transferFrom(
      address(this),
      msg.sender,
      wrapTokenList[wrapTokenId].token_id
    );
  }

  function tokenURI(
    uint256 token_id
  ) public view override returns (string memory) {
    return baseURI;
  }
}
