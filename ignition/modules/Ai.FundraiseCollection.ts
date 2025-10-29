import { buildModule } from "@nomicfoundation/hardhat-ignition/modules";

export default buildModule("Collection", (m) => {
  const bridge = m.contract("AranDAONFTFundraise", [
    "0xCdA1cf578049c46e7A007A0b00e4F5F2fbe419a5", // initialOwner
  ]);

  return { bridge };
});
