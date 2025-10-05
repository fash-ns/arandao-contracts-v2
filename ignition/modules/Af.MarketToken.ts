import { buildModule } from "@nomicfoundation/hardhat-ignition/modules";

export default buildModule("MarketToken", (m) => {
  const bridge = m.contract("AranDAOMarketToken");

  return { bridge };
});
