import { buildModule } from "@nomicfoundation/hardhat-ignition/modules";

export default buildModule("DNMCore", (m) => {
  const c = m.contract("DNMCore", [
    "0xE41AD017Cf9D70746B204dE2046E9BCFAF78AAA9", // initialOwner
    "0xE41AD017Cf9D70746B204dE2046E9BCFAF78AAA9", // _feeReceiver
    "0x4bCB20F928E446cBD05ddD28576299399D82580E", // _arcAddress
    "0xdac17f958d2ee523a2206206994597c13d831ec7", // _paymentTokenAddress
  ]);

  return { c };
});
