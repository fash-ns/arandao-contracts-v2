import { buildModule } from "@nomicfoundation/hardhat-ignition/modules";

export default buildModule("DMarket", (m) => {
  const c = m.contract("DMarket", [
    "0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266", // initialOwner
    "0x3ef9Fdc60762ca76a7f21562244745695172829D", // _marketTokenAddress
    "0x0A3EE490d067C266Ceb6f17aA43bBE7732Ed11c9", // _purchaseTokenAddress
    "0x3AA3DCE3a62fd37Ce28C1120d34A970b371cB69E", // _arcAddress
    "0xe4621D0e194F6E6169e39B3eF1B300de9fBf5d95", // _coreAddress
  ]);

  return { c };
});
