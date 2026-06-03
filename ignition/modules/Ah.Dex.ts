import { buildModule } from "@nomicfoundation/hardhat-ignition/modules";

export default buildModule("Dex", (m) => {
  const c = m.contract("Dex", [
    "0x75080099BBbdE4af79fa08407742D4CD95ea02aA", //_arcToken
    "0x0A3EE490d067C266Ceb6f17aA43bBE7732Ed11c9", //_usdtToken
    "0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266", //_feeReceiver
  ]);

  return { c };
});
