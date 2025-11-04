import { buildModule } from "@nomicfoundation/hardhat-ignition/modules";

export default buildModule("PriceFeed_b1", (m) => {
  const bridge = m.contract("PriceFeed", [
    "0x0f6914d8e7e1214CDb3A4C6fbf729b75C69DF608", // PAXG/USD Feed (ETH/USD in testnet)
    "0xDE31F8bFBD8c84b5360CFACCa3539B938dd78ae6", // WBTC/USD Feed
    "0x4746DeC9e833A82EC7C2C1356372CcF2cfcD2F3D", // DAI/USD Feed
    18n,                                          // Decimals
  ]);

  return { bridge };
});
