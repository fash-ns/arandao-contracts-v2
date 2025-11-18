// // SPDX-License-Identifier: MIT
// pragma solidity ^0.8.30;

// import {Test} from "forge-std/Test.sol";
// import {ShareManager} from "../../src/OrderBook/OrderBookCore/ShareManager.sol";
// import {OrderBookStorage} from "../../src/OrderBook/OrderBookCore/BookStorage.sol";

// contract ShareManagerTest is Test {
//     ShareManagerTestImpl shareManager;

//     address usdt = address(1);
//     address bvRecipient = address(2);
//     address feeRecipient = address(3);

//     function setUp() public {
//         shareManager = new ShareManagerTestImpl(usdt, bvRecipient, feeRecipient);
//     }

//     function testComputeSharesCorrectness() public view {
//         uint256 total = 300; // clean multiple of 150
//         (uint256 seller, uint256 bv, uint256 creator) = shareManager.computeShares(total);

//         // Expected:
//         // seller = 100
//         // bv = 196 (after remainder adjustment)
//         // creator = 71
//         assertEq(seller, 100);
//         assertEq(bv, 146);
//         assertEq(creator, 54);

//         // Sum should equal total exactly
//         assertEq(seller + bv + creator, total);
//     }

//     function testComputeFromSellerCorrectness() public view {
//         uint256 seller = 500;
//         (uint256 bv, uint256 creator, uint256 total) = shareManager.computeFromSeller(seller);

//         // bvGross = 500 * 100 / 50 = 1000
//         // creator = 1000 * 27 / 100 = 270
//         // bv = 1000 - 270 = 730
//         // total = 500 + 730 + 270 = 1500
//         assertEq(bv, 730);
//         assertEq(creator, 270);
//         assertEq(total, 1500);
//     }
// }

// /// @notice Minimal concrete implementation for testing
// contract ShareManagerTestImpl is ShareManager {
//     constructor(address _usdtToken, address _bvRecipient, address _feeRecipient)
//         OrderBookStorage(_usdtToken, _bvRecipient, address(4))
//     {}

//     function computeShares(uint256 total) external pure returns (uint256, uint256, uint256) {
//         return _computeShares(total);
//     }

//     function computeFromSeller(uint256 seller) external pure returns (uint256, uint256, uint256) {
//         return _computeFromSeller(seller);
//     }
// }
