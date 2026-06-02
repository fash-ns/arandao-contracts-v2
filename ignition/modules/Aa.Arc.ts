import { buildModule } from "@nomicfoundation/hardhat-ignition/modules";

export default buildModule("ARC", (m) => {
  const c = m.contract("AssetRightsCoin", [
    "0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266", // initial owner
  ]);

  return { c };
});
