import { buildModule } from "@nomicfoundation/hardhat-ignition/modules";
import { parseEther } from "viem";

export default buildModule("Asc", (m) => {
  const bridge = m.contract("AranDAOStableCoin", [
    "0xf39fd6e51aad88f6f4ce6ab8827279cfffb92266", // initial owner
    parseEther('10000'),                          // Amount of mint for bridge
  ]);

  return { bridge };
});
