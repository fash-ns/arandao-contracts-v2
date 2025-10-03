import { buildModule } from "@nomicfoundation/hardhat-ignition/modules";

export default buildModule("MLMTreeModule", (m) => {
  const mlmTree = m.contract("AranDaoProCore", [
    "0x0000000000000000000000000000000000000000",
    "0x0000000000000000000000000000000000000000",
    "0x0000000000000000000000000000000000000000",
    "0x0000000000000000000000000000000000000000"
  ]);

  return { mlmTree };
});
