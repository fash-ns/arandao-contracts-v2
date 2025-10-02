// SPDX-License-Identifier: MIT
pragma solidity ^0.8.7;

import {Test} from "forge-std/Test.sol";
import {PriceFeed} from "../../src/Vault/VaultCore/PriceFeed.sol";
import {MockV3Aggregator} from "../mocks/MockAggregator.sol";

contract PriceFeedTest is Test {
    PriceFeed priceFeed;

    MockV3Aggregator paxgUsdMock;
    MockV3Aggregator wbtcUsdMock;
    MockV3Aggregator daiUsdMock;

    function setUp() public {
        // All feeds with 8 decimals (like real Chainlink feeds)
        paxgUsdMock = new MockV3Aggregator(8, 2000e8); // PAXG = 2000 USD
        wbtcUsdMock = new MockV3Aggregator(8, 30000e8); // WBTC = 30000 USD
        daiUsdMock = new MockV3Aggregator(8, 1e8); // DAI = 1 USD

        priceFeed = new PriceFeed(address(paxgUsdMock), address(wbtcUsdMock), address(daiUsdMock), 8);
    }

    function testGetPaxgInDai() public {
        uint256 paxgInDai = priceFeed.getPaxgInDai();
        // Expect ~2000 DAI (scaled to 1e18)
        assertEq(paxgInDai, 2000e18);
    }

    function testGetWbtcInDai() public {
        uint256 wbtcInDai = priceFeed.getWbtcInDai();
        // Expect ~30000 DAI (scaled to 1e18)
        assertEq(wbtcInDai, 30000e18);
    }

    function testUpdatePrice() public {
        paxgUsdMock.updateAnswer(2500e8); // new PAXG price
        uint256 paxgInDai = priceFeed.getPaxgInDai();
        assertEq(paxgInDai, 2500e18); // should reflect updated price
    }
}
