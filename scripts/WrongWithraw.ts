import { network } from "hardhat";
import { getContractData } from "../helpers/contractData.js";
import { AranDAOBridge, AssetRightsCoin, MultiAssetVault } from "../types/ethers-contracts/index.js";
import { BaseContract, parseEther } from "ethers";
import { parseError } from "./utils.js";

const { ethers } = await network.connect();
const signers = await ethers.getSigners();
const contractOwner = signers[0];

const withdrawRemainingArc = async () => {
    const bridgeData = getContractData("bridge")
    const bridgeContract = new BaseContract("0x4ACBB80E648d8a6207eae3404deF525fa01bD530", bridgeData.abi, contractOwner) as AranDAOBridge;

    const tx = await bridgeContract.withdrawRemainingArc(parseEther("1098"));
    console.log(tx.hash);
}

const redeemMoney = async () => {
    const vaultData = getContractData("vault")
    const arcData = getContractData("arc")
    
    const vaultContract = new BaseContract("0x300440e547B151Ee2d6Bcf7B80291A67E27b7231", vaultData.abi, contractOwner) as MultiAssetVault;
    const arcContract = new BaseContract("0x32dac6033d31aa9f32e6A006C86b4eD25985922C", arcData.abi, contractOwner) as AssetRightsCoin;

    const arcTx = await arcContract.approve("0x300440e547B151Ee2d6Bcf7B80291A67E27b7231", parseEther("1098"));
    await arcTx.wait(1);

    const tx = await vaultContract.redeemWithBaseTokens(parseEther("1098"));
    console.log(tx.hash);
}

const main = async () => {
    // await withdrawRemainingArc();
    await redeemMoney();
}

main();