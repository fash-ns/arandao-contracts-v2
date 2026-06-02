import { buildModule } from "@nomicfoundation/hardhat-ignition/modules";

export default buildModule("DNMMintedProduct", (m) => {
  const c = m.contract("DNMMintedProduct", []);

  return { c };
});
