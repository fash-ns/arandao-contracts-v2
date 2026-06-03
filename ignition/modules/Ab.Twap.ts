import { buildModule } from "@nomicfoundation/hardhat-ignition/modules";

export default buildModule("TwapOracle", (m) => {
  const c = m.contract("TwapOracle", [
    "0x0A3EE490d067C266Ceb6f17aA43bBE7732Ed11c9", // _token (ARC)
    "0xdac17f958d2ee523a2206206994597c13d831ec7", // _quoteToken (USDT)
    "0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266", // _lpActivator (Address)
    100 * 1e6,                                    // _initialPrice (Price)
    10 * 1e6,                                     // _weeklyIncrement (Price)
    1780272000,                                   // _startTime (Ts)
  ]);

  return { c };
});
