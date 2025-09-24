// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

import {OrderStruct} from "./OrderStruct.sol";
import {UserStruct} from "./UserStruct.sol";
import {SellerStruct} from "./SellerStruct.sol";

contract AranDAOCore {
    mapping(uint256 => OrderStruct.Order) public orders;
    mapping(uint256 => UserStruct.User) public users;
    mapping(uint256 => SellerStruct.Seller) public sellers;
    mapping(address => uint256) public userIds;
    mapping(address => uint256) public sellerIds;

    
}