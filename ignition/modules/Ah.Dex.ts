import { buildModule } from "@nomicfoundation/hardhat-ignition/modules";
import { parseEther } from "viem";

export default buildModule("Dex", (m) => {
  const bridge = m.contract("Dex", [
    "0xf39fd6e51aad88f6f4ce6ab8827279cfffb92266", // initialOwner
    "0xe7f1725E7734CE288F8367e1Bb143E90bb3F0512", // dnmToken
    "0x5FbDB2315678afecb367f032d93F642f64180aa3", // daiToken
    "0xf39fd6e51aad88f6f4ce6ab8827279cfffb92266", // feeReceiver
    "0xDc64a140Aa3E981100a9becA4E685f962f0cF6C9", // vault
    [{
      volumeFloor: 0n,
      feeBps: 10n
    }, {
      volumeFloor: parseEther('10'),
      feeBps: 20n
    }, {
      volumeFloor: parseEther('100'),
      feeBps: 30n
    }, {
      volumeFloor: parseEther('500'),
      feeBps: 40n
    }, {
      volumeFloor: parseEther('1000'),
      feeBps: 100n
    }],                                           // Fees
  ]);

  return { bridge };
});
