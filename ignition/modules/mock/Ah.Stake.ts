import { buildModule } from "@nomicfoundation/hardhat-ignition/modules";

export default buildModule("OldStake", (m) => {
  const bridge = m.contract("StakeMeta", [
    "0xC1248BAbf188f496Cc04ccAe5051c654AD0d23C4",            // uvm_token
    "0x74B78b28F64E13B38212dC3D5F22494CD9b205fe",            // dnm_token
    "0x4734D676A6F9b93445045804FecFbC5E7dea0B56",            // land_token_wrapper
    1759881600,                                              // launch_time
  ]);

  return { bridge };
});
