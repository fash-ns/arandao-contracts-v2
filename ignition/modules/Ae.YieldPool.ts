import { buildModule } from "@nomicfoundation/hardhat-ignition/modules";

export default buildModule("YieldPool", (m) => {
  const c = m.contract("YieldPool", [
    "0x3AA3DCE3a62fd37Ce28C1120d34A970b371cB69E", // _arcToken
    "0x0A3EE490d067C266Ceb6f17aA43bBE7732Ed11c9", // _usdtToken
    "0xe4621D0e194F6E6169e39B3eF1B300de9fBf5d95", // _rewarder (Core)
    "0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266", // _lpActivator (Address)
    "0x7a250d5630B4cF539739dF2C5dAcb4c659F2488D", // _uniswapRouter
  ]);

  return { c };
});
