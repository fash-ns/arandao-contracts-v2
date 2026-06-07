import hre from "hardhat";
import { getContractData } from "../../helpers/contractData.js";
import { NftFundRaiseCollection } from "../../types/ethers-contracts/index.js";

const { ethers } = await hre.network.create();
const signers = await ethers.getSigners();

const owner = signers[0];

const fundraiseCollection = getContractData("fundraiseCollection");
const fundraiseOrderbook = getContractData("fundraiseOrderBook");

const collectionContract = new ethers.BaseContract(fundraiseCollection.address, fundraiseCollection.abi, owner) as NftFundRaiseCollection;

const transferAllowedAddr = await collectionContract.orderBookAddress();

if (transferAllowedAddr != fundraiseOrderbook.address) {
    console.error("Address is wrong");
}

for (let id = 11; id < 20; id++) {
    const addresses = new Array(100).fill("0xEF294AC17E3C0073fAAbd9e119A51E57De6142EE");
    const tokenIds = new Array(100).fill(0).map((_, index) => id * 100 + 1 + index);
    const balances = await collectionContract.balanceOfBatch(addresses, tokenIds);
    balances.forEach(item => {
        if (item !== 1n) {
            console.error("Editions is wrong")
        }
    })
}