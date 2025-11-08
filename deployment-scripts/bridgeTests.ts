import { BaseContract, MaxUint256, parseEther, Signer } from "ethers";
import { network } from "hardhat";
import { getContractData } from "../helpers/contractData.js";
import { AranDAOBridge, AssetRightsCoin, bridge, DNM, UVM, Wrapper } from "../types/ethers-contracts/index.js";
import { parseError } from "./utils.js";

const { ethers } = await network.connect();

const signers = await ethers.getSigners();
const contractOwner = signers[0];
const uvmDnmOwner = signers[1];
const wrapperOwner = signers[2];
const stakeOwner = signers[3];

const transferUvm = async (from: Signer, to: Signer, value: bigint) => {
    const uvmContractData = getContractData("uvm");
    const uvmContract = new BaseContract(uvmContractData.address, uvmContractData.abi, from) as UVM;
    const toAddress = await to.getAddress();
    await uvmContract.transfer(toAddress, value);
}

const getUvmBalance = async (owner: Signer) => {
    const uvmContractData = getContractData("uvm");
    const uvmContract = new BaseContract(uvmContractData.address, uvmContractData.abi, owner) as UVM;
    const ownerAddress = await owner.getAddress();
    const balance = await uvmContract.balanceOf(ownerAddress);
    return balance;
}

const getDnmBalance = async (owner: Signer) => {
    const dnmContractData = getContractData("dnm");
    const dnmContract = new BaseContract(dnmContractData.address, dnmContractData.abi, owner) as DNM;
    const ownerAddress = await owner.getAddress();
    const balance = await dnmContract.balanceOf(ownerAddress);
    return balance;
}

const getArcBalance = async (owner: Signer) => {
    const arcContractData = getContractData("arc");
    const arc = new BaseContract(arcContractData.address, arcContractData.abi, owner) as AssetRightsCoin;
    const ownerAddress = await owner.getAddress();
    const balance = await arc.balanceOf(ownerAddress);
    return balance;
}

const getBalances = async (owner: Signer) => {
    const address = await owner.getAddress();
    const uvmBalance = await getUvmBalance(owner);
    const dnmBalance = await getDnmBalance(owner);
    const arcBalance = await getArcBalance(owner);

    console.log({
        address,
        uvmBalance,
        dnmBalance,
        arcBalance
    })
}

const requestUvmBridge = async () => {
    const bridgeContractData = getContractData("bridge");
    const uvmContractData = getContractData("uvm");

    const uvmContract = new BaseContract(uvmContractData.address, uvmContractData.abi, uvmDnmOwner) as UVM;
    const bridgeContract = new BaseContract(bridgeContractData.address, bridgeContractData.abi, uvmDnmOwner) as AranDAOBridge;

    const uvmBalance = await getUvmBalance(uvmDnmOwner);

    await uvmContract.approve(bridgeContractData.address, uvmBalance);

    try {
        await bridgeContract.bridgeUvm();
    } catch(err: any) {
        console.log(parseError(uvmContractData.abi, err.data));
    }
}

const requestDnmBridge = async () => {
    const bridgeContractData = getContractData("bridge");
    const dnmContractData = getContractData("dnm");

    const dnmContract = new BaseContract(dnmContractData.address, dnmContractData.abi, uvmDnmOwner) as DNM;
    const bridgeContract = new BaseContract(bridgeContractData.address, bridgeContractData.abi, uvmDnmOwner) as AranDAOBridge;

    const dnmBalance = await getDnmBalance(uvmDnmOwner);

    await dnmContract.approve(bridgeContractData.address, dnmBalance);

    try {
        await bridgeContract.bridgeDnm();
    } catch(err: any) {
        console.log(parseError(dnmContractData.abi, err.data));
    }
}

const requestWrapperBridge = async () => {
    const bridgeContractData = getContractData("bridge");
    const wrapperContractData = getContractData("wrapper");

    const wrapperContract = new BaseContract(wrapperContractData.address, wrapperContractData.abi, wrapperOwner) as Wrapper;
    const bridgeContract = new BaseContract(bridgeContractData.address, bridgeContractData.abi, wrapperOwner) as AranDAOBridge;

    await wrapperContract.setApprovalForAll(bridgeContractData.address, true);

    try {
        await bridgeContract.bridgeWrapperToken(912);
    } catch(err: any) {
        console.log(parseError(bridgeContractData.abi, err.data));
    }
}

const requestStakePrincipleBridge = async () => {
    await transferUvm(uvmDnmOwner, stakeOwner, parseEther('2'));
    const bridgeContractData = getContractData("bridge");
    const wrapperContractData = getContractData("wrapper");
    const dnmContractData = getContractData("dnm");
    const uvmContractData = getContractData("uvm");

    const uvmContract = new BaseContract(uvmContractData.address, uvmContractData.abi, uvmDnmOwner) as UVM;
    const dnmContract = new BaseContract(dnmContractData.address, dnmContractData.abi, uvmDnmOwner) as DNM;
    const wrapperContract = new BaseContract(wrapperContractData.address, wrapperContractData.abi, wrapperOwner) as Wrapper;
    const bridgeContract = new BaseContract(bridgeContractData.address, bridgeContractData.abi, wrapperOwner) as AranDAOBridge;

    await uvmContract.approve(bridgeContractData.address, MaxUint256);
    await dnmContract.approve(bridgeContractData.address, MaxUint256);
    await wrapperContract.setApprovalForAll(bridgeContractData.address, true);

    try {
        await bridgeContract.bridgeStakePrinciple(121);
    } catch (err: any) {
        console.log(parseError(bridgeContractData.abi, err.data));
    }
}

const getSnapshots = async () => {
    const bridgeContractData = getContractData("bridge");
    const bridgeContract = new BaseContract(bridgeContractData.address, bridgeContractData.abi, contractOwner) as AranDAOBridge;

    const dnmBalanceSnapshot = await bridgeContract.dnmBalanceByAddressSnapshot("0x5582996842e06d2ef7Cf332d678b85f102Df3D1e");
    const uvmBalanceSnapshot = await bridgeContract.dnmBalanceByAddressSnapshot("0x5582996842e06d2ef7Cf332d678b85f102Df3D1e");

    console.log({
        dnmBalanceSnapshot,
        uvmBalanceSnapshot
    })
}

const withdrawUvm = async () => {
    const bridgeContractData = getContractData("bridge");
    const uvmContractData = getContractData("uvm");

    const bridgeContract = new BaseContract(bridgeContractData.address, bridgeContractData.abi, contractOwner) as AranDAOBridge;
    const uvmContract = new BaseContract(uvmContractData.address, uvmContractData.abi, uvmDnmOwner) as UVM;

    const contractUvmBalance = await uvmContract.balanceOf(bridgeContractData.address);

    console.log(contractUvmBalance);

    try {
        await bridgeContract.withdrawUvm(parseEther('7'));
    } catch (err: any) {
        console.log(parseError(bridgeContractData.abi, err.data));
    }
}

const withdrawDnm = async () => {
    const bridgeContractData = getContractData("bridge");
    const dnmContractData = getContractData("dnm");

    const bridgeContract = new BaseContract(bridgeContractData.address, bridgeContractData.abi, contractOwner) as AranDAOBridge;
    const dnmContract = new BaseContract(dnmContractData.address, dnmContractData.abi, uvmDnmOwner) as DNM;

    const contractDnmBalance = await dnmContract.balanceOf(bridgeContractData.address);

    console.log(contractDnmBalance);

    try {
        await bridgeContract.withdrawDnm(parseEther('1.36'));
    } catch (err: any) {
        console.log(parseError(bridgeContractData.abi, err.data));
    }
}

const withdrawWrapperToken = async () => {
    const bridgeContractData = getContractData("bridge");
    const wrapperContractData = getContractData("wrapper");

    const bridgeContract = new BaseContract(bridgeContractData.address, bridgeContractData.abi, contractOwner) as AranDAOBridge;

    try {
        await bridgeContract.withdrawWrapperToken(912);
    } catch (err: any) {
        console.log(parseError(wrapperContractData.abi, err.data));
    }
}

const main = async () => {
    await requestUvmBridge();
    await requestDnmBridge();
    await requestWrapperBridge();
    await requestStakePrincipleBridge();
    await withdrawUvm();
    await withdrawDnm();
    await withdrawWrapperToken();
    await getBalances(contractOwner);
    await getSnapshots();
}

main();