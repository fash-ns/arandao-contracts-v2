import { network } from "hardhat";
import { getContractData } from "../helpers/contractData.js";
import { BaseContract, parseEther } from "ethers";
import { AssetRightsCoin, core, DNMCore, MultiAssetVault, UVM } from "../types/ethers-contracts/index.js";
import { parseError } from "./utils.js";
import { Result } from "ethers";

const { ethers } = await network.connect();
const signers = await ethers.getSigners();

const daiContractData = getContractData("dai");

  const polContract = new BaseContract(
    "0x0000000000000000000000000000000000001010",
    daiContractData.abi,
    signers[0]
  ) as UVM;

const coreContractData = getContractData("core");
const coreContract = new BaseContract(
    coreContractData.address,
    coreContractData.abi,
    signers[0]
  ) as DNMCore;

const arcContractData = getContractData("arc");
const arcContract = new BaseContract(
    arcContractData.address,
    arcContractData.abi,
    signers[0]
) as AssetRightsCoin;

const vaultContractData = getContractData("vault");
const vaultContract = new BaseContract(
    vaultContractData.address,
    vaultContractData.abi,
    signers[0]
) as MultiAssetVault;

const mintWeeklyArc = async () => {
    // const arcBalanceBefore = await arcContract.balanceOf(coreContractData.address);
    const getGlobalDailySteps1 = await (coreContract as any).getGlobalDailySteps(126);
    const getGlobalDailySteps2 = await (coreContract as any).getGlobalDailySteps(127);
    const getGlobalDailySteps3 = await (coreContract as any).getGlobalDailySteps(128);
    const getGlobalDailySteps4 = await (coreContract as any).getGlobalDailySteps(129);
    const getGlobalDailySteps5 = await (coreContract as any).getGlobalDailySteps(130);
    const getGlobalDailySteps6 = await (coreContract as any).getGlobalDailySteps(131);
    const getGlobalDailySteps7 = await (coreContract as any).getGlobalDailySteps(132);

    console.log([
        getGlobalDailySteps1,
getGlobalDailySteps2,
getGlobalDailySteps3,
getGlobalDailySteps4,
getGlobalDailySteps5,
getGlobalDailySteps6,
getGlobalDailySteps7,
    ])

    const mintAmount = await coreContract.calculateArcMintAmount(18);
    console.log(mintAmount);
    // const tx = await coreContract.mintWeeklyARC();
    // await tx.wait();
    // const arcBalanceAfter = await arcContract.balanceOf(coreContractData.address);

    // const vaultPrice = await vaultContract.getPrice();
    // const arcTotalSupp = await arcContract.totalSupply();
    

    // const vaultBalance = vaultPrice * arcTotalSupp / BigInt("1000000000000000000");

    // console.log({
    //     // arcBalanceBefore,
    //     // mintAmount,
    //     // arcBalanceAfter,
    //     vaultPrice,
    //     arcTotalSupp,
    //     vaultBalance
    // })
}

const arcTotalSup = async () => {
    const arcTotalSupp = await arcContract.totalSupply();
    console.log(arcTotalSupp);
}

const getCoreMintData = async (weekNo: number) => {
    const totalWeekBv = await coreContract.totalWeeklyBv(weekNo);
    console.log(totalWeekBv);
}

const getSellerArcShare = async (sellerId: number, weekNo: number) => {
    const sellerWeeklyBv = await coreContract.sellerWeeklyBv(sellerId, weekNo);
    const totalWeeklyBv = await coreContract.totalWeeklyBv(weekNo);
    const mintedArc = await coreContract.lastWeekArcMintAmount();

    try {
    // const tx = await coreContract.calculateSellerWeeklyArc();
    // await tx.wait();
    const sellerBalance = await arcContract.balanceOf("0x6Bd6a164Bc92632946C33346F0E20B083bcbEfD5");

    const expectedAmount = (mintedArc * BigInt(5) / BigInt(100)) * sellerWeeklyBv / totalWeeklyBv;

    console.log({sellerWeeklyBv,
        totalWeeklyBv,
        mintedArc,
        expectedAmount,
        sellerBalance}
    )
    } catch (err: any) {
        const errLog = parseError(coreContractData.abi, err.data);
        console.log(errLog);
    }
}

const getBuyerArcShare = async (weekNo: number) => {
    const signerAddr = await signers[0].getAddress();
    const userId = await coreContract.getUserIdByAddress(signerAddr);
    const userWeeklyBv = await coreContract.userWeeklyBv(userId, weekNo);
    const totalWeeklyBv = await coreContract.totalWeeklyBv(weekNo);
    const mintedArc = await coreContract.lastWeekArcMintAmount();

    try {
    const tx = await coreContract.calculateUserWeeklyArc();
    await tx.wait();
    const sellerBalance = await arcContract.balanceOf(signerAddr);

    const expectedAmount = (mintedArc * BigInt(35) / BigInt(100)) * userWeeklyBv / totalWeeklyBv;

    console.log({
        signerAddr,
        userWeeklyBv,
        totalWeeklyBv,
        mintedArc,
        expectedAmount,
        sellerBalance
    }
    )
    } catch (err: any) {
        const errLog = parseError(coreContractData.abi, err.data);
        console.log(errLog);
    }
}

const getNetworkerArcShare = async (weekNo: number) => {
    const signerAddr = await signers[0].getAddress();
    const userId = await coreContract.getUserIdByAddress(signerAddr);
    const user = await coreContract.getUserById(userId);
    const mintedArc = await coreContract.lastWeekArcMintAmount();

    try {
    const tx = await coreContract.calculateNetworkerWeeklyARC();
    await tx.wait();
    const userBalance = await arcContract.balanceOf(signerAddr);

    const expectedAmount = (mintedArc * BigInt(60) / BigInt(100)) * BigInt(2) / BigInt(12) * BigInt(70) / BigInt(100);

    console.log({
        signerAddr,
        userSteps: 2,
        globalSteps: 12,
        mintedArc,
        expectedAmount,
        userBalance
    }
    )
    } catch (err: any) {
        const errLog = parseError(coreContractData.abi, err.data);
        console.log(errLog);
    }
}

const getNetworker = async () => {
    const signerAddr = await signers[0].getAddress();
    const userId = await coreContract.getUserIdByAddress(signerAddr);
    const user = await coreContract.getUserById(userId);

    console.log((user as unknown as Result).toObject(true))
}

const limitedMint = async () => {
    await arcContract.limitedMint(parseEther('5'));
}

const transferArc = async () => {
    await arcContract.transfer("0x7d9e97ef4089b73eadfc28e83f7c8b90fc63b22c", parseEther('5'));
}

const transferPol = async () => {
    // await polContract.transfer("0x7d9e97ef4089b73eadfc28e83f7c8b90fc63b22c", parseEther('1'));
    await signers[0].sendTransaction({
        to: "0x7d9e97ef4089b73eadfc28e83f7c8b90fc63b22c",
        value: parseEther("1"),
      });
}

const mintWeeklyArcWithLog = async () => {
    const arcBalanceBefore = await arcContract.balanceOf("0x282B01760c0300e73A88d5466D6DdDAC16Fb7C77");
    await coreContract.mintWeeklyARC();
    const arcBalanceAfter = await arcContract.balanceOf("0x282B01760c0300e73A88d5466D6DdDAC16Fb7C77");

    console.log("SALAM", arcBalanceAfter - arcBalanceBefore);
}

const main = async () => {
    // await mintWeeklyArc();
    // await mintWeeklyArcWithLog();
    // await getCoreMintData(1);
    // await getSellerArcShare(1, 1);
    // await getBuyerArcShare(1);
    // await getNetworkerArcShare(1);
    // await getNetworker();
    // await limitedMint();
    // await transferArc();
    // await transferPol();
    // await arcTotalSup();
    const balance = await polContract.balanceOf(signers[0]);
    console.log(balance);
}

main();