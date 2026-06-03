import { network } from "hardhat";
import { getContractData } from "../helpers/contractData.js";
import { BaseContract, parseEther } from "ethers";
import {
  AssetRightsCoin,
  MultiAssetVault,
} from "../types/ethers-contracts/index.js";
import { parseError } from "./utils.js";

const { ethers } = await network.connect();
const signers = await ethers.getSigners();

const updateSwapEnabled = async () => {
  const vaultContractData = getContractData("vault");
  const vaultContract = new BaseContract(
    vaultContractData.address,
    vaultContractData.abi,
    signers[0],
  ) as MultiAssetVault;

  const tx = await vaultContract.updateSwapEnabled(false);

  console.log(tx.hash);
};

const getVaultBalance = async () => {
  const vaultContractData = getContractData("vault");
  const daiContractData = getContractData("dai");

  const daiContract = new BaseContract(
    daiContractData.address,
    daiContractData.abi,
    signers[0],
  ) as AssetRightsCoin;

  const price = await daiContract.balanceOf(vaultContractData.address);

  console.log(price);
};

const deposit = async () => {
  const vaultContractData = getContractData("vault");
  const daiContractData = getContractData("dai");

  const daiContract = new BaseContract(
    daiContractData.address,
    daiContractData.abi,
    signers[0],
  ) as AssetRightsCoin;
  const vaultContract = new BaseContract(
    vaultContractData.address,
    vaultContractData.abi,
    signers[0],
  ) as MultiAssetVault;

  await daiContract.approve(vaultContractData.address, parseEther("10"));

  const tx = await vaultContract.deposit(parseEther("10"));
  await tx.wait();
};

const depositOperation = async () => {
  await getVaultBalance();
  await deposit();
  await getVaultBalance();
};

// updateSwapEnabled()
// depositOperation();

const coreContractData = getContractData("core");
parseError(coreContractData.abi, "0x55df8c77");
