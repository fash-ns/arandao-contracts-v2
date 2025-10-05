import { buildModule } from "@nomicfoundation/hardhat-ignition/modules";
import { parseEther } from "viem";

export default buildModule("DNM", (m) => {
  const bridge = m.contract("DecentralizedNetworkMarketingPlus", [
    "0xf39fd6e51aad88f6f4ce6ab8827279cfffb92266", // initial owner
    parseEther('500'),                            // Amount of mint for bridge
  ]);

  return { bridge };
});
