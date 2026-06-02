import { network } from "hardhat";
import { DNMCore } from "../types/ethers-contracts/index.js";
import { getContractData } from "../helpers/contractData.js";
import { BaseContract } from "ethers";

const { ethers } = await network.connect();

const signers = await ethers.getSigners();
const owner = signers[0];

const coreContractData = getContractData("core");
const coreContract = new BaseContract(
  coreContractData.address,
  coreContractData.abi,
  owner,
) as DNMCore;

const tx = await coreContract.migrateUser(
  [
    {
      userAddr: "0x13538287bd511e76f9da838a979bc23b877d88ad",
      parentAddr: "0xa9cf6dfe605847393a3ddc6045f3073282ac88b4",
      position: 3,
      bv: ethers.parseEther("100"),
      childrenSafeBv: [0n, 0n, 0n, 0n],
      childrenAggregateBv: [0n, 0n, 0n, 0n],
      normalNodesBv: [0n, 0n],
    },
  ],
  {
    // gasPrice: parseUnits("60", "gwei"),
    // nonce: 252
  },
);
console.log("TX", tx.hash);
