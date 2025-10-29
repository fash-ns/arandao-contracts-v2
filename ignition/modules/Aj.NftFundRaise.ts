import { buildModule } from "@nomicfoundation/hardhat-ignition/modules";

export default buildModule("OrderBook_b1", (m) => {
  const bridge = m.contract("NFTOrderBook", [
    "0xCdA1cf578049c46e7A007A0b00e4F5F2fbe419a5", // initialOwner
    "0xab23d706A06a8dF824C6b8433B652753e8E07A91", // daiToken
    "0x74d65191d80E904dc9Eb6A1674B03FA482178a30", // bvRecipient
    "0xf5D0855De893Abda892DA296c3d3E847CC926AcD", // feeRecipient
    167n,                                         // denom
    50n,                                          // sellerNum
    100n,                                         // bvNum
    0n,                                           // minimumPrice
  ]);

  return { bridge };
});
