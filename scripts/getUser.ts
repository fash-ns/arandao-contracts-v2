import hre from "hardhat";
import { getContractData } from "../helpers/contractData.js";
import { BaseContract } from "ethers";
import { DNMCore } from "../types/ethers-contracts/index.js";

const { ethers } = await hre.network.create();
const signers = await ethers.getSigners();

const getUserById = async (id: number) => {
    const core = getContractData("core");
    const coreContract = new BaseContract(core.address, core.abi, signers[0]) as DNMCore;

    const user = await coreContract.getUserById(id);

    console.log((user as any).toObject());
}

getUserById(3598);