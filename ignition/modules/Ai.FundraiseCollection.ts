import { buildModule } from "@nomicfoundation/hardhat-ignition/modules";

export default buildModule("NftFundRaiseCollection", (m) => {
  const c = m.contract("NftFundRaiseCollection", [
    "0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266", //initialOwner
    "0x0A3EE490d067C266Ceb6f17aA43bBE7732Ed11c9", //usdtAddr
  ]);

  return { c };
});
