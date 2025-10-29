import { buildModule } from "@nomicfoundation/hardhat-ignition/modules";

export default buildModule("Market", (m) => {
  const bridge = m.contract("AranDAOMarket", [
    "0x66A6466066495AaD26fb791f69c94eC9BF6b38b0", // marketTokenAddress
  ]);

  //TODO: Call setMarketTokenAddress

  return { bridge };
});
