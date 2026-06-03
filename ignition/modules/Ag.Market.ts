import { buildModule } from "@nomicfoundation/hardhat-ignition/modules";

export default buildModule("DMarket", (m) => {
  const c = m.contract("DMarket", [
    "0xb9b147cc108D03871F7DaA3B15A697511a19F501", // _marketTokenAddress
    "0x0A3EE490d067C266Ceb6f17aA43bBE7732Ed11c9", // _purchaseTokenAddress
    "0x75080099BBbdE4af79fa08407742D4CD95ea02aA", // _arcAddress
    "0xF6B601A5D02701308613C234244A9a3327EeA2fa", // _coreAddress
  ]);

  return { c };
});
