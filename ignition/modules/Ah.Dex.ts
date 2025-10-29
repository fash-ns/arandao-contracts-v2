import { buildModule } from "@nomicfoundation/hardhat-ignition/modules";
import { parseEther } from "viem";

export default buildModule("Dex_b1", (m) => {
  const bridge = m.contract("Dex", [
    "0xCdA1cf578049c46e7A007A0b00e4F5F2fbe419a5", // initialOwner
    "0x569D5b74557F8923bBefde4c249CAE55Fab181A5", // dnmToken
    "0xab23d706A06a8dF824C6b8433B652753e8E07A91", // daiToken
    "0xf5D0855De893Abda892DA296c3d3E847CC926AcD", // feeReceiver
    "0x5929077459bBb22C636ed6f7Dd410ef6f5D4532E", // vault
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
