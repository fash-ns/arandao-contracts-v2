import { buildModule } from "@nomicfoundation/hardhat-ignition/modules";

export default buildModule("DNMCore", (m) => {
  const c = m.contract("DNMCore", [
    "0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266", // initialOwner
    "0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266", // _feeReceiver
    "0x75080099BBbdE4af79fa08407742D4CD95ea02aA", // _arcAddress
    "0x0A3EE490d067C266Ceb6f17aA43bBE7732Ed11c9", // _paymentTokenAddress
  ]);

  return { c };
});
