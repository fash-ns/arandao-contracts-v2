import { buildModule } from "@nomicfoundation/hardhat-ignition/modules";

export default buildModule("Market", (m) => {
  const bridge = m.contract("AranDAOMarket", [
    "0x0165878A594ca255338adfa4d48449f69242Eb8F", // marketTokenAddress
  ]);

  return { bridge };
});
