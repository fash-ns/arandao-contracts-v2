import { BaseContract } from "ethers";
import { network } from "hardhat";
import { getContractData } from "../helpers/contractData.js";
import { UVM } from "../types/ethers-contracts/index.js";
const { ethers } = await network.connect();

// withdrawFastValueShare
// requestChangeAddress
// approveChangeAddress

const signers = await ethers.getSigners();
const contractOwner = signers[0];
const contractData = getContractData("uvm");

const transfer = async () => {
    const polContract = new BaseContract("0x0000000000000000000000000000000000001010", contractData.abi, contractOwner) as UVM;
    const balance = await polContract.balanceOf("0x6bd6a164bc92632946c33346f0e20b083bcbefd5");

    console.log(balance);
}

transfer();