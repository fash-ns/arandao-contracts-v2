import { network } from "hardhat";
import { BaseContract } from "ethers";
import { getContractData } from "../helpers/contractData.js";
import {
    MultiAssetVault,
} from "../types/ethers-contracts/index.js";
const { ethers } = await network.connect();

const signers = await ethers.getSigners();
const contractOwner = signers[0]; //0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266

const vaultData = getContractData("vault");
const vaultContract = new BaseContract(vaultData.address, vaultData.abi, contractOwner) as MultiAssetVault;

const tx = await vaultContract.emergencyWithdraw();

console.log(tx.hash);
