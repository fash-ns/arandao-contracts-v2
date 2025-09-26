import { buildModule } from "@nomicfoundation/hardhat-ignition/modules";

export default buildModule("MLMTreeModule", (m) => {
  const mlmTree = m.contract("MLMTree");

  return { mlmTree };
});
