import { buildModule } from "@nomicfoundation/hardhat-ignition/modules";

export default buildModule("BridgeModule", (m) => {
  const bridge = m.contract("AranDAOBridge", [
    "0xC1248BAbf188f496Cc04ccAe5051c654AD0d23C4", // UVM address
    "0x74B78b28F64E13B38212dC3D5F22494CD9b205fe", // Dnm address
    "0x4734D676A6F9b93445045804FecFbC5E7dea0B56", // Wrapper token address
    "0xC89f2610137d83Ecc8F3eb7595f79CfEdaC8d633", // Stake address
    "0x569D5b74557F8923bBefde4c249CAE55Fab181A5", // New DNM address
  ]);

  return { bridge };
});
