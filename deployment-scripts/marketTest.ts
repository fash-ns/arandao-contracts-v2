import { network } from "hardhat";
import { getContractData } from "../helpers/contractData.js";
import { BaseContract, parseEther, Result } from "ethers";
import { DNMCore, AssetRightsCoin, DMarket, MultiAssetVault, UVM } from "../types/ethers-contracts/index.js";
import { parseError } from "./utils.js";
const { ethers } = await network.connect();

// withdrawFastValueShare
// requestChangeAddress
// approveChangeAddress

const signers = await ethers.getSigners();
const contractOwner = signers[0];        //0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266
const sellerSigner = signers[1];         //0x5582996842e06d2ef7Cf332d678b85f102Df3D1e
const buyerSigner = signers[2];          //0xdFa0C8A616025b1621ADcC52183031E94C6f1C51
const thirdSigner = signers[3];          //0xf8499823A84162aAc6646f63c296e5D1f8088ab5
const farbodSigner = signers[4];         //0x5E642CA96e24eB5A0e80ca45C6221d8410e3916C
const newSigner = signers[5];            //0xC4ad083BB6606A72563A792E7219744693f260ec
const daiHolderSigner = signers[6];      //0x9DB3937aE12adf8ADbE18035C2dE7d77c4d2242B

const testSigner1 = signers[7];          //0x995033d0c3a951f78b52eae2a07ab71217ed2e00
const testSigner2 = signers[8];          //0x5078864179bb9ef2d9298f3b0e0a307c0591cae9
const testSigner3 = signers[9];          //0x45bf11c2d5db8287098a9da98a47ea42ce50c8b4

const transferDai = async () => {
    const daiContractData = getContractData("dai");

    const daiContract = new BaseContract(daiContractData.address, daiContractData.abi, farbodSigner) as UVM;
    const polContract = new BaseContract("0x0000000000000000000000000000000000001010", daiContractData.abi, farbodSigner) as UVM;
    const newAddr = await newSigner.getAddress();

    await contractOwner.sendTransaction({
        to: "0xC4ad083BB6606A72563A792E7219744693f260ec",
        value: parseEther("1")
      });
    await contractOwner.sendTransaction({
        to: "0x995033d0c3a951f78b52eae2a07ab71217ed2e00",
        value: parseEther("1")
      });
    await contractOwner.sendTransaction({
        to: "0x5078864179bb9ef2d9298f3b0e0a307c0591cae9",
        value: parseEther("1")
      });
    await contractOwner.sendTransaction({
        to: "0x45bf11c2d5db8287098a9da98a47ea42ce50c8b4",
        value: parseEther("1")
      });

    await daiContract.transfer('0x995033d0c3a951f78b52eae2a07ab71217ed2e00', parseEther('150'));
    await daiContract.transfer('0x5078864179bb9ef2d9298f3b0e0a307c0591cae9', parseEther('150'));
    await daiContract.transfer('0x45bf11c2d5db8287098a9da98a47ea42ce50c8b4', parseEther('150'));

    await polContract.transfer(newAddr, parseEther('1'));
}

const createProduct = async () => {
    const marketContractData = getContractData("market");
    const marketContract = new BaseContract(marketContractData.address, marketContractData.abi, sellerSigner) as DMarket;

    try {
        await marketContract.createProduct(parseEther("2"), parseEther("2"), "100", "QmbWqxBEKC3P8tqsKc98xmWNzrzDtRLMiMPL8wBuTGsMnR");
    } catch (err: any) {
        console.log(parseError(marketContractData.abi, err.data));
    }
}

const createProduct2 = async () => {
    const marketContractData = getContractData("market");
    const marketContract = new BaseContract(marketContractData.address, marketContractData.abi, farbodSigner) as DMarket;

    try {
        await marketContract.createProduct(parseEther("3"), parseEther("2"), "100", "QmbWqxBEKC3P8tqsKc98xmWNzrzDtRLMiMPL8wBuTGsMnR");
    } catch (err: any) {
        console.log(parseError(marketContractData.abi, err.data));
    }
}

const lockArc = async () => {
    const arcContractData = getContractData("arc");
    const marketContractData = getContractData("market");

    const marketContract = new BaseContract(marketContractData.address, marketContractData.abi, sellerSigner) as DMarket;
    const arcContract = new BaseContract(arcContractData.address, arcContractData.abi, sellerSigner) as AssetRightsCoin;

    await arcContract.approve(marketContractData.address, parseEther('2'));

    try {
        await marketContract.lockSellerArc();
    } catch (err: any) {
        console.log(parseError(marketContractData.abi, err.data));
    }
}

const lockArc2 = async () => {
    const arcContractData = getContractData("arc");
    const marketContractData = getContractData("market");

    const marketContract = new BaseContract(marketContractData.address, marketContractData.abi, farbodSigner) as DMarket;
    const arcContract = new BaseContract(arcContractData.address, arcContractData.abi, farbodSigner) as AssetRightsCoin;

    await arcContract.approve(marketContractData.address, parseEther('2'));

    try {
        await marketContract.lockSellerArc();
    } catch (err: any) {
        console.log(parseError(marketContractData.abi, err.data));
    }
}

const withdrawArc = async () => {
    const marketContractData = getContractData("market");

    const marketContract = new BaseContract(marketContractData.address, marketContractData.abi, sellerSigner) as DMarket;
    try {
        await marketContract.withdrawSellerArc();
    } catch (err: any) {
        console.log(parseError(marketContractData.abi, err.data));
    }
}

const purchaseProductThroughBuyer = async () => {
    const marketContractData = getContractData("market");
    const coreContractData = getContractData('core');
    const daiContractData = getContractData("dai");

    const marketContract = new BaseContract(marketContractData.address, marketContractData.abi, farbodSigner) as DMarket;
    const daiContract = new BaseContract(daiContractData.address, daiContractData.abi, farbodSigner) as UVM;

    await daiContract.approve(marketContractData.address, parseEther('201'));
    
    try {
        await marketContract.purchaseProduct([
            {productId: 1, quantity: 1}
        ], "0x50FBc531a4b37fB912A379B310720441f58e5A56", 0)
    } catch (err: any) {
        console.log(parseError(coreContractData.abi, err.data));
    }
}

const purchaseProductThroughBuyer2 = async () => {
    const marketContractData = getContractData("market");
    const coreContractData = getContractData('core');
    const daiContractData = getContractData("dai");

    const marketContract = new BaseContract(marketContractData.address, marketContractData.abi, testSigner1) as DMarket;
    const daiContract = new BaseContract(daiContractData.address, daiContractData.abi, testSigner1) as UVM;

    await daiContract.approve(marketContractData.address, parseEther('201'));
    
    try {
        await marketContract.purchaseProduct([
            {productId: 2, quantity: 1}
        ], "0x50FBc531a4b37fB912A379B310720441f58e5A56", 3)
    } catch (err: any) {
        console.log(parseError(marketContractData.abi, err.data));
    }
}

const purchaseProductThroughNewUser = async () => {
    const marketContractData = getContractData("market");
    const coreContractData = getContractData('core');
    const daiContractData = getContractData("dai");

    const marketContract = new BaseContract(marketContractData.address, marketContractData.abi, testSigner2) as DMarket;
    const daiContract = new BaseContract(daiContractData.address, daiContractData.abi, testSigner2) as UVM;

    await daiContract.approve(marketContractData.address, parseEther('201'));
    
    try {
        await marketContract.purchaseProduct([
            {productId: 2, quantity: 3}
        ], "0x5E642CA96e24eB5A0e80ca45C6221d8410e3916C", 0)
    } catch (err: any) {
        console.log(parseError(coreContractData.abi, err.data));
    }
}

const purchaseProductThroughAnotherNewUser = async () => {
    const marketContractData = getContractData("market");
    const coreContractData = getContractData('core');
    const daiContractData = getContractData("dai");

    const marketContract = new BaseContract(marketContractData.address, marketContractData.abi, testSigner3) as DMarket;
    const daiContract = new BaseContract(daiContractData.address, daiContractData.abi, testSigner3) as UVM;

    await daiContract.approve(marketContractData.address, parseEther('100'));
    
    try {
        await marketContract.purchaseProduct([
            {productId: 1, quantity: 3}
        ], "0x5E642CA96e24eB5A0e80ca45C6221d8410e3916C", 3)
    } catch (err: any) {
        // console.log(err);
        console.log(parseError(marketContractData.abi, err.data));
    }
}

const getProductById = async (id: bigint) => {
    const marketContractData = getContractData("market");

    const marketContract = new BaseContract(marketContractData.address, marketContractData.abi, sellerSigner) as DMarket;
    const product = await marketContract.products(id);

    console.log((product as unknown as Result).toObject(true));
}

const getUserIdByAddress = async (addr: string) => {
    const buyerAddr = await buyerSigner.getAddress();
    const coreContractData = getContractData("core");

    const coreContract = new BaseContract(coreContractData.address, coreContractData.abi, sellerSigner) as DNMCore;

    const userId = await coreContract.getUserIdByAddress(addr);
    console.log(userId);

}

const getUserById = async (id: bigint) => {
    const coreContractData = getContractData("core");

    const coreContract = new BaseContract(coreContractData.address, coreContractData.abi, sellerSigner) as DNMCore;

    const user = await coreContract.getUserById(id);
    console.log((user as any).toObject(true));
}

const getSellerById = async (id: bigint) => {
    const coreContractData = getContractData("core");

    const coreContract = new BaseContract(coreContractData.address, coreContractData.abi, sellerSigner) as DNMCore;

    const seller = await coreContract.getSellerById(id);
    console.log((seller as any).toObject(true));
}

const getOrderById = async (id: bigint) => {
    const coreContractData = getContractData("core");

    const coreContract = new BaseContract(coreContractData.address, coreContractData.abi, sellerSigner) as DNMCore;

    const order = await coreContract.getOrderById(id);
    console.log((order as any).toObject(true));
}

const calculateOrders = async () => {
    const coreContractData = getContractData("core");

    const coreContract = new BaseContract(coreContractData.address, coreContractData.abi, contractOwner) as DNMCore;

    try {
        await coreContract.calculateOrders(5128, new Array(19).fill(0).map((_, index) => index + 1));
    } catch (err: any) {
        console.log(parseError(coreContractData.abi, err.data));
    }

}

const mintWeeklyArc = async () => {
    const coreContractData = getContractData("core");

    const coreContract = new BaseContract(coreContractData.address, coreContractData.abi, contractOwner) as DNMCore;
    try {
        await coreContract.mintWeeklyARC();
    } catch (err: any) {
        console.log(parseError(coreContractData.abi, err.data));
    }
}

const withdrawNetworkerCommission = async () => {
    const coreContractData = getContractData("core");

    const coreContract = new BaseContract(coreContractData.address, coreContractData.abi, sellerSigner) as DNMCore;
    await coreContract.withdrawCommission(parseEther('3'));
}

const getArcTotalSupply = async () => {
    const arcContractData = getContractData("arc");
    const arcContract = new BaseContract(arcContractData.address, arcContractData.abi, sellerSigner) as AssetRightsCoin;

    const totalSup = await arcContract.totalSupply();

    console.log(totalSup);
}

const getVaultPrice = async () => {
    const vaultContractData = getContractData("vault");
    const vaultContract = new BaseContract(vaultContractData.address, vaultContractData.abi, contractOwner) as MultiAssetVault;
    const price = await vaultContract.getPrice();

    console.log(price);
}

const emergencyWithdraw = async () => {
    const vaultContractData = getContractData("vault");
    const daiContractData = getContractData("dai");
    const vaultContract = new BaseContract(vaultContractData.address, vaultContractData.abi, contractOwner) as MultiAssetVault;
    const daiContract = new BaseContract(daiContractData.address, daiContractData.abi, contractOwner) as UVM;
    const paxgContract = new BaseContract("0x553d3d295e0f695b9228246232edf400ed3560b5", daiContractData.abi, contractOwner) as UVM;
    const wbtcContract = new BaseContract("0x1bfd67037b42cf73acf2047067bd4f2c47d9bfd6", daiContractData.abi, contractOwner) as UVM;

    const ownerAddr = await contractOwner.getAddress();

    const daiBalanceBeforeWithdrawal = await daiContract.balanceOf(ownerAddr);

    await vaultContract.emergencyWithdraw();

    const daiBalanceAfterWithdrawal = await daiContract.balanceOf(ownerAddr);
    const paxgBalance = await paxgContract.balanceOf(ownerAddr);
    const wbtcBalance = await wbtcContract.balanceOf(ownerAddr);

    console.log({
        daiBalanceBeforeWithdrawal,
        daiBalanceAfterWithdrawal,
        paxgBalance,
        wbtcBalance,
    })
}

const withdrawSellerArc = async () => {
    const sellerAddr = await sellerSigner.getAddress();
    console.log(sellerAddr);

    const coreContractData = getContractData("core");

    const coreContract = new BaseContract(coreContractData.address, coreContractData.abi, sellerSigner) as DNMCore;

    try {
        await coreContract.calculateSellerWeeklyArc();
    } catch (err: any) {
        console.log(parseError(coreContractData.abi, err.data));
    }
}

const withdrawBuyerArc = async () => {
    const coreContractData = getContractData("core");

    const coreContract = new BaseContract(coreContractData.address, coreContractData.abi, buyerSigner) as DNMCore;

    try {
        await coreContract.calculateUserWeeklyArc();
    } catch (err: any) {
        console.log(parseError(coreContractData.abi, err.data));
    }
}

const withdrawNetworkerArc = async () => {
    const coreContractData = getContractData("core");

    const coreContract = new BaseContract(coreContractData.address, coreContractData.abi, sellerSigner) as DNMCore;

    try {
        await coreContract.calculateNetworkerWeeklyARC();
    } catch (err: any) {
        console.log(parseError(coreContractData.abi, err.data));
    }
}

const monthlyWithdrawNetworkerArc = async () => {
    const coreContractData = getContractData("core");

    const coreContract = new BaseContract(coreContractData.address, coreContractData.abi, sellerSigner) as DNMCore;

    try {
        await coreContract.monthlyWithdrawNetworkerArc();
    } catch (err: any) {
        console.log(parseError(coreContractData.abi, err.data));
    }
}

const getMintedArcAmount = async () => {
    const coreContractData = getContractData("core");

    const coreContract = new BaseContract(coreContractData.address, coreContractData.abi, sellerSigner) as DNMCore;
    
    const amount = await coreContract.lastWeekDnmMintAmount();

    console.log(amount);
}

const getArcBalance = async (address: string) => {
    const buyerAddr = await buyerSigner.getAddress();
    console.log(buyerAddr);
    const arcContractData = getContractData("arc");
    const arcContract = new BaseContract(arcContractData.address, arcContractData.abi, sellerSigner) as AssetRightsCoin;

    const balance = await arcContract.balanceOf(address);
    console.log(balance);
}

const requestChangeAddress = async () => {
    const coreContractData = getContractData("core");

    const coreContract = new BaseContract(coreContractData.address, coreContractData.abi, sellerSigner) as DNMCore;

    try {
        await coreContract.requestChangeAddress("0xC4ad083BB6606A72563A792E7219744693f260ec");
    } catch (err: any) {
        console.log(parseError(coreContractData.abi, err.data));
    }
}

const coreEmergencyWithdraw = async () => {
    const coreContractData = getContractData("core");

    const coreContract = new BaseContract(coreContractData.address, coreContractData.abi, contractOwner) as DNMCore;

    try {
        await coreContract.emergencyWithdraw();
    } catch (err: any) {
        console.log(parseError(coreContractData.abi, err.data));
    }
}

const approveChangeAddress = async () => {
    const coreContractData = getContractData("core");

    const coreContract = new BaseContract(coreContractData.address, coreContractData.abi, farbodSigner) as DNMCore;

    try {
        await coreContract.approveChangeAddress(1);
    } catch (err: any) {
        console.log(parseError(coreContractData.abi, err.data));
    }
}

const withdrawFvShare = async () => {
    const coreContractData = getContractData("core");

    const coreContract = new BaseContract(coreContractData.address, coreContractData.abi, farbodSigner) as DNMCore;

    try {
        await coreContract.withdrawFastValueShare(5522);
    } catch (err: any) {
        console.log(parseError(coreContractData.abi, err.data));
    }
}

const getFvShares = async () => {
    const coreContractData = getContractData("core");

    const coreContract = new BaseContract(coreContractData.address, coreContractData.abi, farbodSigner) as DNMCore;

    const share = await coreContract.monthlyUserShares(5527, 5128);

    console.log(share);
}

const getBvs = async () => {
    const coreContractData = getContractData("core");

    const coreContract = new BaseContract(coreContractData.address, coreContractData.abi, farbodSigner) as DNMCore;

    const weeklyCalculationStartTime = await coreContract.weeklyCalculationStartTime();
    const _maxSteps = await coreContract._maxSteps();
    const _bvBalance = await coreContract._bvBalance();
    const _commissionPerStep = await coreContract._commissionPerStep();
    const _minBv = await coreContract._minBv();

    console.log(`weeklyCalculationStartTime: ${weeklyCalculationStartTime}`);
    console.log(`_maxSteps: ${_maxSteps}`);
    console.log(`_bvBalance: ${_bvBalance}`);
    console.log(`_commissionPerStep: ${_commissionPerStep}`);
    console.log(`_minBv: ${_minBv}`);
}

const depositVault = async () => {
    const vaultContractData = getContractData("vault");
    const daiContractData = getContractData("dai");

    const vaultContract = new BaseContract(vaultContractData.address, vaultContractData.abi, farbodSigner) as MultiAssetVault;
    const daiContract = new BaseContract(daiContractData.address, daiContractData.abi, farbodSigner) as UVM;

    await daiContract.approve(vaultContractData.address, parseEther('100'));

    await vaultContract.deposit(parseEther('100'));

    const balance = await vaultContract.getPrice();

    console.log((balance * BigInt(1108)))

}

const main = async () => {
    // await lockArc();
    // await lockArc2();
    // await createProduct();
    // await createProduct2();
    // await transferDai();
    await depositVault();
    // await withdrawArc();
    // await getProductById(1n);
    // await purchaseProductThroughBuyer();
    // await purchaseProductThroughBuyer2();
    // for (let i = 0; i < 9; i++) {
    //     await purchaseProductThroughNewUser();
    //     await purchaseProductThroughAnotherNewUser();    
    // }
    // await calculateOrders();
    // await getBvs();
    // await withdrawFvShare();
    // await getFvShares();
    // await mintWeeklyArc();

    // await withdrawNetworkerCommission();
    // await withdrawNetworkerArc();
    // await monthlyWithdrawNetworkerArc();

    // await requestChangeAddress();
    // await approveChangeAddress();
    // await coreEmergencyWithdraw();

    // await getOrderById(20n);
    // await getUserById(5128n);
    // await getSellerById(1n);
    // await withdrawSellerArc();
    // await withdrawSellerArc();
    // await getMintedArcAmount();
    // await getArcTotalSupply();

    // await getVaultPrice();
    // await emergencyWithdraw();
    // await getUserIdByAddress("0x5E642CA96e24eB5A0e80ca45C6221d8410e3916C");

    // await withdrawBuyerArc();

    // await getArcBalance("0x5582996842e06d2ef7Cf332d678b85f102Df3D1e");

    // await getOrderById(12n);
}

farbod: 9.180
seller: 5.9

main();