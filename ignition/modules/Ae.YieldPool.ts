import { buildModule } from "@nomicfoundation/hardhat-ignition/modules";

export default buildModule("YieldPool", (m) => {
  const c = m.contract("YieldPool", [
    "0x75080099BBbdE4af79fa08407742D4CD95ea02aA", // _arcToken
    "0x0A3EE490d067C266Ceb6f17aA43bBE7732Ed11c9", // _usdtToken
    "0xF6B601A5D02701308613C234244A9a3327EeA2fa", // _rewarder (Core)
    "0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266", // _lpActivator (Address)
    "0x7a250d5630B4cF539739dF2C5dAcb4c659F2488D", // _uniswapRouter
  ]);

  return { c };
});
