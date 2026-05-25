import {network} from "hardhat";
import collectionAbi from "../artifacts/contracts/collection/Collection.sol/NftFundRaiseCollection.json";
import { NftFundRaiseCollection } from "../types/ethers-contracts/index.js";
// import data from "../personal/tokenData.json";

const {ethers} = await network.create();
const signers = await ethers.getSigners();

const collectionContract = new ethers.BaseContract("0xc1A26F85582308753487C7F0Ec672A2aA37eeabE", collectionAbi.abi, signers[0]) as NftFundRaiseCollection;

const data: Array<any> = [];

for (let i = 0; i < 5; i++) {
    const slicer = 200;
    const dataSet = data.slice(i * slicer, (i + 1) * slicer)
    console.log(`From ${i * slicer} to ${(i + 1) * slicer}`)
    const balance = await collectionContract.balanceOfBatch(dataSet.map(ind => ind.walletAddress), dataSet.map(ind => ind.blockchainTokenId));
    balance.forEach((item, index) => {
        if (item !== 1n) {
            console.warn(`Wrong info for token ID ${i * slicer + index + 1}`);
        }
    })
}