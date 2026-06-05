import { buildModule } from "@nomicfoundation/hardhat-ignition/modules";

export default buildModule("NFTFundRaiseOrderBook", (m) => {
  const c = m.contract("NFTFundRaiseOrderBook", [
    "0xdac17f958d2ee523a2206206994597c13d831ec7", // paymentToken
    "0x4cCFbF5DDa901876Ca4415E7cbcBE70349BD216F", // coreContractAddress
    "0xef18157c255dCa18D07117AAed4Ea828787Ce7D1", // collectionAddr
  ]);

  return { c };
});