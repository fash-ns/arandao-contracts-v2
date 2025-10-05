import { buildModule } from "@nomicfoundation/hardhat-ignition/modules";

export default buildModule("BridgeModule", (m) => {
  const bridge = m.contract("AranDAOBridge", [
    "0x0000000000000000000000000000000000000000", // UVM address
    "0x0000000000000000000000000000000000000000", // Dnm address
    "0x0000000000000000000000000000000000000000", // Wrapper token address
    "0x0000000000000000000000000000000000000000", // Stake address
    "0xe7f1725E7734CE288F8367e1Bb143E90bb3F0512", // New DNM address
  ]);

  return { bridge };
});
