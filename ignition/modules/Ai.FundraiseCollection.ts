import { buildModule } from "@nomicfoundation/hardhat-ignition/modules";

export default buildModule("Collection", (m) => {
  const bridge = m.contract("AranDAONFTFundraise", [
    "0xf39fd6e51aad88f6f4ce6ab8827279cfffb92266", // initialOwner
  ]);

  return { bridge };
});
