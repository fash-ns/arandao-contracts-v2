import { buildModule } from "@nomicfoundation/hardhat-ignition/modules";

export default buildModule("PriceFeed_b1", (m) => {
  const bridge = m.contract("PriceFeed", [
    "0xC5981F461d74c46eB4b0CF3f4Ec79f025573B0Ea", // PAXG/USD Feed (ETH/USD in testnet)
    "0x1b44F3514812d835EB1BDB0acB33d3fA3351Ee43", // WBTC/USD Feed
    "0x14866185B1962B63C3Ea9E03Bc1da838bab34C19", // DAI/USD Feed
    18n,                                          // Decimals
  ]);

  return { bridge };
});
