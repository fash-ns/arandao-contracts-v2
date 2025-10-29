import { network } from "hardhat";

const { viem } = await network.connect({
  network: "localhost",
  // network: "hardhatMainnet",
  chainType: "l1",
});

