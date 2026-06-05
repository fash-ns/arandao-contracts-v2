import { buildModule } from "@nomicfoundation/hardhat-ignition/modules";

export default buildModule("Dex", (m) => {
  const c = m.contract("Dex", [
    "0x4bCB20F928E446cBD05ddD28576299399D82580E", //_arcToken
    "0xdac17f958d2ee523a2206206994597c13d831ec7", //_usdtToken
    "0xE41AD017Cf9D70746B204dE2046E9BCFAF78AAA9", //_feeReceiver
  ]);

  return { c };
});
