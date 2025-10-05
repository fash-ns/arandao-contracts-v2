import { buildModule } from "@nomicfoundation/hardhat-ignition/modules";

export default buildModule("Core", (m) => {
  const bridge = m.contract("AranDaoProCore", [
    "0xf39fd6e51aad88f6f4ce6ab8827279cfffb92266", // initAdmin
    "0xe7f1725E7734CE288F8367e1Bb143E90bb3F0512", // dnmAddress
    "0x5FbDB2315678afecb367f032d93F642f64180aa3", // paymentTokenAddress
    "0xDc64a140Aa3E981100a9becA4E685f962f0cF6C9", // vaultAddress
  ]);

  return { bridge };
});
