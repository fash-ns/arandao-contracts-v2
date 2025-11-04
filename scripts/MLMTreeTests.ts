import { network } from "hardhat";

const { viem } = await network.connect({
  network: "localhost",
  // network: "hardhatMainnet",
  chainType: "op",
});

const uvmAddress = await viem.getContractAt("DNM", "0x8f3Cf7ad23Cd3CaDbD9735AFf958023239c6A063");

const balance = await uvmAddress.read.balanceOf(['0x5E642CA96e24eB5A0e80ca45C6221d8410e3916C'])

console.log({balance})