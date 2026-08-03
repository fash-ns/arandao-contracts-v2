import { buildModule } from "@nomicfoundation/hardhat-ignition/modules";

export default buildModule("FastValueV2", (m) => {
  const c = m.contract("FastValue", [
    "0xdac17f958d2ee523a2206206994597c13d831ec7", // _paymentTokenAddress
    "0x4cCFbF5DDa901876Ca4415E7cbcBE70349BD216F", // _coreContractAddress
  ]);

  return { c };
});
