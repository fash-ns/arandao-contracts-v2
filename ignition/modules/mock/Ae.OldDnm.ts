import { buildModule } from "@nomicfoundation/hardhat-ignition/modules";

export default buildModule("OldDNM", (m) => {
  const bridge = m.contract("DNM", [
    "AranDao old DNM token",            // Name
    "OldDNM",                           // Symbol
  ]);

  //TODO: Mint DNM

  return { bridge };
});
