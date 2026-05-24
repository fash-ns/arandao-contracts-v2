import { BaseContract, parseEther } from "ethers";
import {network} from "hardhat";
import { getContractData } from "../helpers/contractData.js";
import { DNMCore } from "../types/ethers-contracts/index.js";

const { ethers } = await network.connect();
const signers = await ethers.getSigners();

const main = async () => {
    const coreContractData = getContractData("core");

    const coreContract = new BaseContract(coreContractData.address, coreContractData.abi, signers[0]) as DNMCore;

    // const tx = await coreContract.updateTotalCommissionEarned(parseEther("120"));
    // const totalCommissionEarned = await coreContract.totalCommissionEarned();

    // console.log(totalCommissionEarned);
    const res = await coreContract.totalArcEarned();

    console.log(res);
}

main();