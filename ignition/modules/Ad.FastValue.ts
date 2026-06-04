import { buildModule } from "@nomicfoundation/hardhat-ignition/modules";

export default buildModule("FastValue", (m) => {
  const c = m.contract("FastValue", [
    "0x0A3EE490d067C266Ceb6f17aA43bBE7732Ed11c9", // _paymentTokenAddress
    "0xe4621D0e194F6E6169e39B3eF1B300de9fBf5d95", // _coreContractAddress
  ]);

  return { c };
});
