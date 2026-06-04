import { buildModule } from "@nomicfoundation/hardhat-ignition/modules";

export default buildModule("TwapOracle", (m) => {
  const c = m.contract("TwapOracle", [
    "0x3AA3DCE3a62fd37Ce28C1120d34A970b371cB69E", // _token (ARC)
    "0x0A3EE490d067C266Ceb6f17aA43bBE7732Ed11c9", // _quoteToken (USDT)
    "0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266", // _lpActivator (Address)
    100 * 1e6, // _initialPrice (Price)
    10 * 1e6, // _weeklyIncrement (Price)
    1780272000, // _startTime (Ts)
  ]);

  return { c };
});
