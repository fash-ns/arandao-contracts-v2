import { buildModule } from "@nomicfoundation/hardhat-ignition/modules";

export default buildModule("MarketToken", (m) => {
  const bridge = m.contract("AranDAOMarketToken");

  //TODO: Add market to mintOperators after deploy

  return { bridge };
});
