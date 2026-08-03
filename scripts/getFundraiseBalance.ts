import hre from "hardhat";
import { BaseContract } from "ethers";
import { getContractData } from "../helpers/contractData.js";
import { NftFundRaiseCollection } from "../types/ethers-contracts/index.js";

const { ethers } = await hre.network.create();
const signers = await ethers.getSigners();

const owner = signers[0];

const fundraiseCollection = getContractData("fundraiseCollection");
const collectionContract = new BaseContract(fundraiseCollection.address, fundraiseCollection.abi, owner) as NftFundRaiseCollection;

const address = "0x76b34b7d6Bd27234AD23C434d7F5ABc83B32CA4D";
const tokenid = 62;

const balance = await collectionContract.balanceOf(address, tokenid);
console.log(balance);