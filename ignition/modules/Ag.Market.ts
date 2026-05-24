import { buildModule } from "@nomicfoundation/hardhat-ignition/modules";

export default buildModule("Market", (m) => {
  const bridge = m.contract("DMarket", [
    "0xf39fd6e51aad88f6f4ce6ab8827279cfffb92266", // Initial Owner
    "0x66A6466066495AaD26fb791f69c94eC9BF6b38b0", // marketTokenAddress
  ]);

  //TODO: Call setMarketTokenAddress

  return { bridge };
});
