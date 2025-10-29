import { buildModule } from "@nomicfoundation/hardhat-ignition/modules";
import { parseEther } from "viem";

export default buildModule("DNM", (m) => {
  const bridge = m.contract("DecentralizedNetworkMarketingPlus", [
    "0xCdA1cf578049c46e7A007A0b00e4F5F2fbe419a5", // initial owner
    parseEther('500'),                            // Amount of mint for bridge
  ]);

  return { bridge };
});
