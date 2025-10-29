import { buildModule } from "@nomicfoundation/hardhat-ignition/modules";

export default buildModule("Core_b2", (m) => {
  const bridge = m.contract("AranDaoProCore", [
    "0xCdA1cf578049c46e7A007A0b00e4F5F2fbe419a5", // initAdmin
    "0x569D5b74557F8923bBefde4c249CAE55Fab181A5", // dnmAddress
    "0xab23d706A06a8dF824C6b8433B652753e8E07A91", // paymentTokenAddress
    "0x5929077459bBb22C636ed6f7Dd410ef6f5D4532E", // vaultAddress
  ]);

  return { bridge };
});
