import { buildModule } from "@nomicfoundation/hardhat-ignition/modules";

export default buildModule("NFTFundRaiseOrderBook", (m) => {
  const c = m.contract("NFTFundRaiseOrderBook", [
    "0x0A3EE490d067C266Ceb6f17aA43bBE7732Ed11c9", // paymentToken
    "0xF6B601A5D02701308613C234244A9a3327EeA2fa", // coreContractAddress
    "0x03D963421D0A31838467bce5B034BC34Ab258CBe", // collectionAddr
  ]);

  return { c };
});
