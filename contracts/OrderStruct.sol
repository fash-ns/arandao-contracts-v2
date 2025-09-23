// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

contract OrdersStruct {
    struct NewOrder {
        uint256 userId;
        uint256 sellerId;
        uint256 bv;
        uint256 uv;
        uint256 fv;
        bytes32 data;
    }

    struct Order {
        uint256 id;
        uint256 userId;
        uint256 sellerId;
        uint256 bv;
        uint256 uv;
        uint256 fv;
        uint256 date;
        bytes32 data;
        bool exists;
    }

    event OrderCreated (
        uint256 indexed id,
        uint256 indexed sellerId,
        uint256 indexed userId,
        uint256 bv,
        uint256 uv,
        uint256 fv
    );
}