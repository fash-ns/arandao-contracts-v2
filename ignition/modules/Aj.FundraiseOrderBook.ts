import { buildModule } from "@nomicfoundation/hardhat-ignition/modules";

export default buildModule("NFTFundRaiseOrderBook", (m) => {
  const c = m.contract("NFTFundRaiseOrderBook", [
    "0x0A3EE490d067C266Ceb6f17aA43bBE7732Ed11c9", // paymentToken
    "0xe4621D0e194F6E6169e39B3eF1B300de9fBf5d95", // coreContractAddress
    "0x5bf75299DbCadbEbCb6f0A9F9a1fE1C2B4bD9722", // collectionAddr
  ]);

  return { c };
});