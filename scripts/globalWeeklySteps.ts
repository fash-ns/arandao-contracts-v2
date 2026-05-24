import { network } from "hardhat";
import { getContractData } from "../helpers/contractData.js";
import { BaseContract } from "ethers";
import { DNMCore } from "../types/ethers-contracts/index.js";
const { ethers } = await network.connect();
const signers = await ethers.getSigners();
const signer = signers[0]

const coreContractData = getContractData("core");
const coreContract = new BaseContract(coreContractData.address, coreContractData.abi, signer) as DNMCore;

const calculateWeekSteps = async (weekNo: number) => {
    let weekSteps = 0;

    for (let i = 0; i < 7; i++) {
        let dayNumber = weekNo * 7 + i;
        const dailySteps = await coreContract.getGlobalDailySteps(dayNumber);
        weekSteps += parseInt(dailySteps.toString());
    }
    return weekSteps
}

const main = async () => {
    for (let i = 1; i < 26; i++) {
        const weekSteps = await calculateWeekSteps(i);
        console.log(`${i}: ${weekSteps}`);
    }
}

main();