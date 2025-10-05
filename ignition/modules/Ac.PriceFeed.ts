import { buildModule } from "@nomicfoundation/hardhat-ignition/modules";

export default buildModule("PriceFeed", (m) => {
  const bridge = m.contract("PriceFeed", [
    "0xF0d50568e3A7e8259E16663972b11910F89BD8e7", // PAXG/USD Feed (ETH/USD in testnet)
    "0xe7656e23fE8077D438aEfbec2fAbDf2D8e070C4f", // WBTC/USD Feed
    "0x1896522f28bF5912dbA483AC38D7eE4c920fDB6E", // DAI/USD Feed
    18n,                                          // Decimals
  ]);

  return { bridge };
});
