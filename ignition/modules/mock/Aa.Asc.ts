import { buildModule } from "@nomicfoundation/hardhat-ignition/modules";
import { parseEther } from "viem";

export default buildModule("Asc", (m) => {
  const bridge = m.contract("AranDAOStableCoin", [
    "0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266", // initial owner
    1000000,                          // Amount of mint for bridge
  ]);

  return { bridge };
});
