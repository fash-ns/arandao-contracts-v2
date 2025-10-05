import { buildModule } from "@nomicfoundation/hardhat-ignition/modules";

export default buildModule("OrderBook", (m) => {
  const bridge = m.contract("NFTOrderBook", [
    "0xf39fd6e51aad88f6f4ce6ab8827279cfffb92266", // initialOwner
    "0x5FbDB2315678afecb367f032d93F642f64180aa3", // daiToken
    "0x5FC8d32690cc91D4c39d9d3abcBD16989F875707", // bvRecipient
    "0x5FC8d32690cc91D4c39d9d3abcBD16989F875707", // feeRecipient
    167n,                                         // denom
    50n,                                          // sellerNum
    100n,                                         // bvNum
    0n,                                           // minimumPrice
  ]);

  return { bridge };
});
