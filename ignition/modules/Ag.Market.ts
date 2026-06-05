import { buildModule } from "@nomicfoundation/hardhat-ignition/modules";

export default buildModule("DMarket", (m) => {
  const c = m.contract("DMarket", [
    "0xd4d7c4258b0d93B2375599Aff3F502C181b9bc2E", // _marketTokenAddress
    "0xdac17f958d2ee523a2206206994597c13d831ec7", // _purchaseTokenAddress
    "0x4bCB20F928E446cBD05ddD28576299399D82580E", // _arcAddress
    "0x4cCFbF5DDa901876Ca4415E7cbcBE70349BD216F", // _coreAddress
  ]);

  return { c };
});
