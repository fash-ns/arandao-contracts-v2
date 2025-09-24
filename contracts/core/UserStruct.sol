// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

library UserStruct {
  struct ImportUser {
    uint256[4] childrenBv;
    uint256[4] childrenAggrigateBv;
    uint256[2] normalNodesBv;
    uint8 position;
    uint256 bv;
    uint256 dnmWithdraw;
    address userAddress;
    address parentAddress;
    address referrerAddress;
  }

  struct BusinessValue {
    uint256[4] childrenBv; //Calculated by real user nodes BV
    uint256[4] childrenAggrigateBv; //Calculated by user nodes BV, It's total BV
    uint256[2] normalNodesBv; //Calculated for the own user normal nodes
    uint256 userBv; //User's own BV from buying products
  }

  struct LastOrder {
    uint256 date;
    uint256 id;
  }

  struct User {
    uint256 parentId;
    uint256 referrerId;
    address userAddress;
    address[4] children;
    BusinessValue bv;
    LastOrder lastOrder;
    uint256 depth;
    bool exists;
  }

  event UserCreated(
    address indexed userAddress,
    uint256 indexed userId,
    address parentAddress,
    uint8 position
  );

  error ParentNotExists(address parentAddress);
  error ReferrerNotExists(address parentAddress);
  error UserAlreadyExists(address userAddress, uint256 userId);
  error PositionIsNotUnlockedByParent(uint8 position);
}
