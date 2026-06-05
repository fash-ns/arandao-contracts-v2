import { buildModule } from "@nomicfoundation/hardhat-ignition/modules";

export default buildModule("YieldPool", (m) => {
  const c = m.contract("YieldPool", [
    "0x4bCB20F928E446cBD05ddD28576299399D82580E", // _arcToken
    "0xdac17f958d2ee523a2206206994597c13d831ec7", // _usdtToken
    "0x4cCFbF5DDa901876Ca4415E7cbcBE70349BD216F", // _rewarder (Core)
    "0xE41AD017Cf9D70746B204dE2046E9BCFAF78AAA9", // _lpActivator (Address)
    "0x7a250d5630B4cF539739dF2C5dAcb4c659F2488D", // _uniswapRouter
  ]);

  return { c };
});
