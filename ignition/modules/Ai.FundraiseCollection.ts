import { buildModule } from "@nomicfoundation/hardhat-ignition/modules";

export default buildModule("NftFundRaiseCollection", (m) => {
  const c = m.contract("NftFundRaiseCollection", [
    "0xEF294AC17E3C0073fAAbd9e119A51E57De6142EE", //initialOwner
    "0xdac17f958d2ee523a2206206994597c13d831ec7", //usdtAddr
  ]);

  return { c };
});
