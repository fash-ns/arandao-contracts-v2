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

const getUserIdByAddress = async (address: string) => {
    const core = getContractData("core");
    const coreContract = new BaseContract(core.address, core.abi, signers[0]) as DNMCore;

    const user = await coreContract.getUserIdByAddress(address);

    console.log(user);
}

// getUserIdByAddress('0x8d50d592df1044841a56454dbadd73447836fc11');
getUserById(5272);