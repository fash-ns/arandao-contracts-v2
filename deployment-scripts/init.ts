import { BaseContract, BigNumberish, parseEther, parseUnits } from "ethers";
import { network } from "hardhat";

import { AranDAOBridge, DNMCore, DNMMintedProduct, AssetRightsCoin, DMarket, NftFundRaiseCollection } from "../types/ethers-contracts/index.js";
import userData from "../personal/userData.json";
import uvm from "../personal/uvm.json";
import dnm from "../personal/dnm.json";
import wrapperTokens from "../personal/wrapperTokens.json";
import stakes from "../personal/stakes.json";
import { parseError } from "./utils.js";
import { getContractData } from "../helpers/contractData.js";

const { ethers } = await network.connect();

const signers = await ethers.getSigners();
const owner = signers[0];
const seller = signers[1];
const buyerSigner = signers[2];
const thirdSigner = signers[3];
const farbodSigner = signers[4];
const newSigner = signers[5];


const addMarketToMarketTokenMintOperators = async () => {
    const marketTokenContractData = getContractData("mintedProduct");
    const marketContractData = getContractData("market");
    const marketTokenContract = new BaseContract(marketTokenContractData.address, marketTokenContractData.abi, owner) as DNMMintedProduct;
    await marketTokenContract.setMintOperator(marketContractData.address);
}

const setMarketAddresses = async () => {
    const marketContractData = getContractData("market");
    const marketTokenContractData = getContractData("mintedProduct");
    const daiContractData = getContractData("dai");
    const arcContractData = getContractData("arc");
    const coreContractData = getContractData("core");
    const marketContract = new BaseContract(marketContractData.address, marketContractData.abi, owner) as DMarket;
    
    try {
        await marketContract.setMarketTokenAddress(marketTokenContractData.address, daiContractData.address, arcContractData.address, coreContractData.address);
    } catch(err: any) {
        console.log(parseError(marketContractData.abi, err.data));
        throw new Error("Error");
    }
}

const setFundraiseCollectionTransferAllowedAddresses = async () => {
    const orderBookContractData = getContractData("fundraiseMarket");
    const collectionContractData = getContractData("fundraiseToken");

    const collectionContract = new BaseContract(collectionContractData.address, collectionContractData.abi, owner) as NftFundRaiseCollection;

    await collectionContract.addTransferAllowedAddress(orderBookContractData.address);
}

const setVaultAddressForCore = async () => {
    const coreContractData = getContractData("core");
    const vaultContractData = getContractData("vault");

    const coreContract = new BaseContract(coreContractData.address, coreContractData.abi, owner) as DNMCore;
    const tx = await coreContract.setVaultAddress(vaultContractData.address);
    console.log(tx.hash);
}

const addCoreAsARCMintOperator = async () => {
    const arcContractData = getContractData("arc");
    const coreContractData = getContractData("core");

    const arcContract = new BaseContract(arcContractData.address, arcContractData.abi, owner) as AssetRightsCoin;
    await arcContract.setMintOperator(coreContractData.address);
}

const transferArcToBridge = async () => {
    const arcContractData = getContractData('arc');
    const bridgeContractData = getContractData('bridge');

    const arcContract = new BaseContract(arcContractData.address, arcContractData.abi, owner) as AssetRightsCoin;

    try {
        await arcContract.transfer(bridgeContractData.address, parseEther('1100'));
        //TODO: COmment
        // const sellerAddress = await seller.getAddress();
        // await arcContract.transfer(sellerAddress, parseEther('4'));
    
        // const farbodAddress = await farbodSigner.getAddress();
        // await arcContract.transfer(farbodAddress, parseEther('4'));
    } catch(e: any) {
        console.log(parseError(arcContractData.abi, e.data));
    }
}

const sleep = async (ts: number) => {
    return new Promise<void>((resolve) => {
        setTimeout(() => {
            resolve();
        }, 5000)
    })
}

const migrateUsers = async () => {
    const coreContractData = getContractData("core");
    const coreContract = new BaseContract(coreContractData.address, coreContractData.abi, owner) as DNMCore;

    for (let i = 20; i < Math.ceil(userData.length / 100); i++) {
        console.log(`Migrating user from ${i * 100} to ${Math.min((i + 1) * 100, userData.length)}`)
        try {
            const tx = await coreContract.migrateUser(userData.slice(i * 100, Math.min((i + 1) * 100, userData.length)).map(user => ({
                userAddr: user.userAddr,
                parentAddr: user.parentAddr,
                position: user.position,
                bv: user.bv,
                childrenSafeBv: user.childrenSafeBv as [BigNumberish, BigNumberish, BigNumberish, BigNumberish],
                childrenAggregateBv: user.childrenAggregateBv as [BigNumberish, BigNumberish, BigNumberish, BigNumberish],
                normalNodesBv: user.normalNodesBv as [BigNumberish, BigNumberish]
            })), {gasPrice: parseUnits("120", "gwei")});
            console.log("TX", tx.hash);
            await sleep(10000);
        } catch (err: any) {
            console.log(parseError(coreContractData.abi, err.data));
            break;
        }
    }
}

const getBridgeContract = () => {
    const bridgeContractData = getContractData("bridge");
    return {
        contract: new BaseContract(bridgeContractData.address, bridgeContractData.abi, owner) as AranDAOBridge,
        data: bridgeContractData
    }
}

const addMarketToCoreOrderCreator = async () => {
    const coreContractData = getContractData("core");
    const marketContractData = getContractData("market");
    const fundraiseCollectionContractData = getContractData("fundraiseMarket");

    const coreContract = new BaseContract(coreContractData.address, coreContractData.abi, owner) as DNMCore;
    await coreContract.addWhiteListedContract(marketContractData.address);
    await coreContract.addWhiteListedContract(fundraiseCollectionContractData.address);
}

const addBridgeDNMSnapshot = async () => {
    const bridgeContract = getBridgeContract();
    for (let i = 0; i < Math.ceil(dnm.length / 100); i++) {
        console.log(`Importing DNM snapshots from ${i * 100} to ${Math.min((i + 1) * 100, dnm.length)}`)
        try {
            let addresses: string[] = [];
            let amounts: string[] = [];
            dnm.slice(i * 100, Math.min((i + 1) * 100, dnm.length)).forEach(dnmAmount => {
                addresses.push(dnmAmount.walletAddress);
                amounts.push(dnmAmount.dnmBalance);
            })
    
            await bridgeContract.contract.snapshotDnm(addresses, amounts)
        } catch (err: any) {
            console.log(parseError(bridgeContract.data.abi, err.data));
            break;
        }
    }
}

const addBridgeUVMSnapshot = async () => {
    const bridgeContract = getBridgeContract();
    for (let i = 0; i < Math.ceil(uvm.length / 100); i++) {
        console.log(`Importing UVM snapshots from ${i * 100} to ${Math.min((i + 1) * 100, uvm.length)}`)
        try {
            let addresses: string[] = [];
            let amounts: string[] = [];
            uvm.slice(i * 100, Math.min((i + 1) * 100, uvm.length)).forEach(uvmAmount => {
                addresses.push(uvmAmount.walletAddress);
                amounts.push(uvmAmount.uvmBalance);
            })
    
            await bridgeContract.contract.snapshotUvm(addresses, amounts)
        } catch (err: any) {
            console.log(parseError(bridgeContract.data.abi, err.data));
            break;
        }
    }
}

const addBridgeWrapperTokenSnapshot = async () => {
    const bridgeContract = getBridgeContract();
    for (let i = 0; i < Math.ceil(wrapperTokens.length / 100); i++) {
        console.log(`Importing Wrapper tokens snapshots from ${i * 100} to ${Math.min((i + 1) * 100, wrapperTokens.length)}`)
        try {
            let addresses: string[] = [];
            let amounts: number[][] = [];
            wrapperTokens.slice(i * 100, Math.min((i + 1) * 100, wrapperTokens.length)).forEach(wrapperToken => {
                addresses.push(wrapperToken.walletAddress);
                amounts.push(wrapperToken.tokenIds);
            })
    
            await bridgeContract.contract.snapshotWrapperToken(addresses, amounts)
        } catch (err: any) {
            console.log(parseError(bridgeContract.data.abi, err.data));
            break;
        }
    }
}

const addBridgeStakeSnapshot = async () => {
    const bridgeContract = getBridgeContract();
    for (let i = 0; i < Math.ceil(stakes.length / 100); i++) {
        console.log(`Importing stakes snapshots from ${i * 100} to ${Math.min((i + 1) * 100, stakes.length)}`)
        try {
            let stakeIds: number[] = [];
            let stakeValues: any[] = [];
            stakes.slice(i * 100, Math.min((i + 1) * 100, stakes.length)).forEach(stake => {
                stakeIds.push(stake.id);
                stakeValues.push({
                    userAddress: stake.userAddress,
                    exists: stake.exists,
                    totalPaidOut: stake.totalPaidOut,
                    principleWithdrawn: stake.principleWithdrawn
                });
            })
    
            await bridgeContract.contract.snapshotStake(stakeIds, stakeValues);
        } catch (err: any) {
            console.log(parseError(bridgeContract.data.abi, err.data));
            break;
        }
    }
}

const finishSnapshotTaking = async () => {
    const bridgeContract = getBridgeContract();
    await bridgeContract.contract.finishSnapshotTaking();
}

const main = async () => {
    // console.log("addMarketToMarketTokenMintOperators");
    // await addMarketToMarketTokenMintOperators();
    // console.log("setMarketAddresses");
    // await setMarketAddresses();
    // console.log("setFundraiseCollectionTransferAllowedAddresses");
    // await setFundraiseCollectionTransferAllowedAddresses();
    console.log("setVaultAddressForCore");
    await setVaultAddressForCore();
    // console.log("transferArcToBridge");
    // await transferArcToBridge();
    // console.log("migrateUsers");
    // await migrateUsers();
    // console.log("addBridgeDNMSnapshot");
    // await addBridgeDNMSnapshot();
    // console.log("addBridgeUVMSnapshot");
    // await addBridgeUVMSnapshot();
    // console.log("addBridgeWrapperTokenSnapshot");
    // await addBridgeWrapperTokenSnapshot();
    // console.log("addBridgeStakeSnapshot");
    // await addBridgeStakeSnapshot();
    // console.log("finishSnapshotTaking");
    // await finishSnapshotTaking();
    // console.log("addMarketToCoreOrderCreator");
    // await addMarketToCoreOrderCreator();
    // console.log("addCoreAsARCMintOperator");
    // await addCoreAsARCMintOperator();
    console.log("Done");
}

main();