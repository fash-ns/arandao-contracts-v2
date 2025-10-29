import { buildModule } from "@nomicfoundation/hardhat-ignition/modules";

export default buildModule("OldWrapperToken", (m) => {
  const bridge = m.contract("Wrapper", [
    "ipfs://",            // Base url
  ]);

  return { bridge };
});
