import { network } from "hardhat";
import { getContractData } from "../helpers/contractData.js";
import { BaseContract, parseEther } from "ethers";
import { AssetRightsCoin } from "../types/ethers-contracts/index.js";

const { ethers } = await network.connect();
const signers = await ethers.getSigners();
const contractOwner = signers[0];

const limitedMint = async () => {
    const arcData = getContractData("arc");
    const arcContract = new BaseContract(arcData.address, arcData.abi, contractOwner) as AssetRightsCoin;

    const tx = await arcContract.limitedMint(parseEther("10"));

    console.log(tx.hash);

    await tx.wait(1);
}

limitedMint();