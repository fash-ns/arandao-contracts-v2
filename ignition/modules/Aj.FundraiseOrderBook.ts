import { buildModule } from "@nomicfoundation/hardhat-ignition/modules";

export default buildModule("NFTFundRaiseOrderBook", (m) => {
  const c = m.contract("NFTFundRaiseOrderBook", [
    "0xdac17f958d2ee523a2206206994597c13d831ec7", // paymentToken
    "0x4cCFbF5DDa901876Ca4415E7cbcBE70349BD216F", // coreContractAddress
    "0x5b8135DeD8893a975f9F41473d69f7743962f85E", // collectionAddr
  ]);

  return { c };
});