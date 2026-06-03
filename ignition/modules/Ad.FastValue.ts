import { buildModule } from "@nomicfoundation/hardhat-ignition/modules";

export default buildModule("FastValue", (m) => {
  const c = m.contract("FastValue", [
    "0x0A3EE490d067C266Ceb6f17aA43bBE7732Ed11c9", // _paymentTokenAddress
    "0xF6B601A5D02701308613C234244A9a3327EeA2fa", // _coreContractAddress
  ]);

  return { c };
});
