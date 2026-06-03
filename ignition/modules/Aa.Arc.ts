import { buildModule } from "@nomicfoundation/hardhat-ignition/modules";

export default buildModule("ARC", (m) => {
  const c = m.contract("AssetRightsCoin", [
  ]);

  return { c };
});
