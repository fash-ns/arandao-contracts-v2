import { network } from "hardhat";
import { BaseContract } from "ethers";
import { getContractData } from "../helpers/contractData.js";
import { DNMCore, MultiAssetVault } from "../types/ethers-contracts/index.js";

const { ethers } = await network.connect();
const signers = await ethers.getSigners();
const contractOwner = signers[0];

const upgradeTime = async () => {
    const coreData = getContractData("core");
    const vaultData = getContractData("vault");
    const contract = new BaseContract("0xa131dc15f221cf99fa366f2E4E8A2424939a94D0", vaultData.abi, contractOwner) as MultiAssetVault;

    const tx = await contract.shiftUpgradeDeadline();
    console.log(tx.hash);
    await tx.wait(1);
}

upgradeTime();