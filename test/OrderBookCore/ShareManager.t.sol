// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import "forge-std/Test.sol";
import {ShareManager} from "../../src/OrderBookCore/ShareManager.sol";
import {OrderBookStorage} from "../../src/OrderBookCore/BookStorage.sol";


contract ShareManagerTest is Test {
    ShareManagerTestImpl shareManager;

    address usdt = address(1);
    address bvRecipient = address(2);
    address feeRecipient = address(3);

    function setUp() public {
        shareManager = new ShareManagerTestImpl(usdt, bvRecipient, feeRecipient);
    }

    function testComputeSharesCorrectness() public view {
        uint256 total = 400; // simple multiple of DENOM to avoid rounding
        (uint256 seller, uint256 bv, uint256 creator) = shareManager.computeShares(total);

        // Seller = total * 50 / 167 = 500
        // BV     = total * 100 / 167 = 1000
        // Creator = total - seller - bv = 170
        assertEq(seller, 119);
        assertEq(bv, 239);
        assertEq(creator, 42);

        // Sum should equal total
        assertEq(seller + bv + creator, total);
    }

    function testComputeFromSellerCorrectness() public view {
        uint256 seller = 500;
        (uint256 bv, uint256 creator, uint256 total) = shareManager.computeFromSeller(seller);

        // bv = seller * 100 / 50 = 1000
        // creator = seller * 17 / 50 = 170
        // total = 500 + 1000 + 170 = 1670
        assertEq(bv, 1000);
        assertEq(creator, 170);
        assertEq(total, 1670);
    }

}

/// @notice Minimal concrete implementation for testing
contract ShareManagerTestImpl is ShareManager {
    constructor(
        address _usdtToken,
        address _bvRecipient,
        address _feeRecipient
    )
        OrderBookStorage(_usdtToken, _bvRecipient, _feeRecipient, 167, 50, 100, 1000)
    {}

    function computeShares(uint256 total) external view returns (uint256, uint256, uint256) {
        return _computeShares(total);
    }

    function computeFromSeller(uint256 seller) external view returns (uint256, uint256, uint256) {
        return _computeFromSeller(seller);
    }
}