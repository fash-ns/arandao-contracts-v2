import { buildModule } from "@nomicfoundation/hardhat-ignition/modules";

export default buildModule("Vault", (m) => {
  const bridge = m.contract("MultiAssetVault", [
    "0x5FbDB2315678afecb367f032d93F642f64180aa3", // dai
    "0x0000000000000000000000000000000000000000", // paxg
    "0x0000000000000000000000000000000000000000", // wbtc
    "0xe7f1725E7734CE288F8367e1Bb143E90bb3F0512", // dnm
    "0xCf7Ed3AccA5a467e9e704C703E8D87F634fB0Fc9", // feedAddr
    "0x0000000000000000000000000000000000000000", // routerAddr
    "0xf39fd6e51aad88f6f4ce6ab8827279cfffb92266", // admin1
    "0x70997970c51812dc3a010c7d01b50e0d17dc79c8", // admin2
    "0x3c44cdddb6a900fa2b585dd299e03d12fa4293bc", // admin3
    "0x90f79bf6eb2c4f870365e785982e1f101e93b906", // feeReceiver
  ]);

  return { bridge };
});
