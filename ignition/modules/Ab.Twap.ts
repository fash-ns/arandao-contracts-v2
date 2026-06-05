import { buildModule } from "@nomicfoundation/hardhat-ignition/modules";

export default buildModule("TwapOracle", (m) => {
  const c = m.contract("TwapOracle", [
    "0x4bCB20F928E446cBD05ddD28576299399D82580E", // _token (ARC)
    "0xdac17f958d2ee523a2206206994597c13d831ec7", // _quoteToken (USDT)
    "0xE41AD017Cf9D70746B204dE2046E9BCFAF78AAA9", // _lpActivator (Address)
    90 * 1e6, // _initialPrice (Price)
    10 * 1e6, // _weeklyIncrement (Price)
    1780272000, // _startTime (Ts)
  ]);

  return { c };
});
