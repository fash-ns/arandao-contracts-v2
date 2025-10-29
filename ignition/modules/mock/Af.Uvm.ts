import { buildModule } from "@nomicfoundation/hardhat-ignition/modules";

export default buildModule("OldUVM", (m) => {
  const bridge = m.contract("UVM", [
    "AranDao old UVM token",            // Name
    "OldUVM",                           // Symbol
    10000                               // Initial supply
  ]);

  return { bridge };
});
