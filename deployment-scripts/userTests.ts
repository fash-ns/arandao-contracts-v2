import { network } from "hardhat";

const { ethers } = await network.connect();

const signers = await ethers.getSigners();
const contractOwner = signers[0];
const parent = signers[1];
const parent2 = signers[2];

const main = async () => {

}

main();