import { network } from "hardhat";
import { getContractData } from "../helpers/contractData.js";
import { BaseContract, parseEther, parseUnits, Result } from "ethers";
import {
  DNMCore,
  AssetRightsCoin,
  DMarket,
  MultiAssetVault,
  UVM,
  AranDAOBridge,
} from "../types/ethers-contracts/index.js";
import { parseError } from "./utils.js";
const { ethers } = await network.connect();

const signers = await ethers.getSigners();

const checkApproval = async () => {
    const arcContractData = getContractData('arc');

    const contract = new BaseContract(arcContractData.address, arcContractData.abi, signers[0]) as AssetRightsCoin;

    const allowance = await contract.allowance("0xD5A49be076e72A772d9F78dFf77b8943E4b4E082", "0x6CE5ce6D69620AC43805bc6a84867daEC23E0c9B");
    console.log(allowance);
}

const lockSellerArc = async () => {
    const arcContractData = getContractData('arc');
    const marketContractData = getContractData("market");

    
    const arcContract = new BaseContract(arcContractData.address, arcContractData.abi, signers[2]) as AssetRightsCoin;
    const balance = await arcContract.balanceOf(marketContractData.address);
    console.log({balance});
    await arcContract.approve(marketContractData.address, 2000000000000000000n);


    const marketContract = new BaseContract(marketContractData.address, marketContractData.abi, signers[2]) as DMarket;
    await marketContract.lockSellerArc();

}

const a = async () => {
    const txHash = "0xd4916c0b00b8077378df703e31563aaa40da1237cef45d32e35b5e27e75fc3a3";
    const tx = await ethers.provider.getTransaction(txHash);
    // const txReceipt = await ethers.provider.getTransactionReceipt(txHash);
    // console.log(txReceipt);
    console.log(tx?.from);
    const data = getContractData("fundraiseMarket");
    const iface = new ethers.Interface(data.abi);
  
    const parsedTxData = iface.parseTransaction({data: tx?.data!})
  
    console.log(parsedTxData);
  }

const getUserCommissions = async () => {
  const coreContractData = getContractData("core");
  const contract = new BaseContract(coreContractData.address, coreContractData.abi, signers[0]) as DNMCore;
  let userId = 2600;

  while (true) {
    console.log(`Fetching user id ${userId}`);
    const user = await contract.getUserById(userId);
    if (!user.active) break;
    if (user.withdrawableCommission !== BigInt(0)) {
      console.log(`UserId ${userId} has ${user.withdrawableCommission} commission to withdraw`);
    }
    userId++;
  }
}
  
// a();
// getUserCommissions();
// checkApproval();
// lockSellerArc();

const contractData = getContractData("dai");
parseError(contractData.abi, "0xfb8f41b2000000000000000000000000fcc26d363e231303fd879a6431b2a5aac70ef4d50000000000000000000000000000000000000000000000024dce54d34a1a00000000000000000000000000000000000001e17b84357691b6403d0da800000000");