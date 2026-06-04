import hre from "hardhat";
import { getContractData } from "../helpers/contractData.js";
import { BaseContract, parseEther } from "ethers";
import { AranDAOStableCoin, AssetRightsCoin, DMarket, DNMCore, DNMMintedProduct } from "../types/ethers-contracts/index.js";

const { ethers } = await hre.network.create();
const signers = await ethers.getSigners();

const sellerSigner = signers[1];
const buyerSigner = signers[2];

async function clearEip7702Delegation(address: string) {
    await ethers.provider.send("anvil_setCode", [address, "0x"]);
}

const getEthBalance = async () => {
    const sellerBalance = await ethers.provider.getBalance(sellerSigner.address);
    const buyerBalance = await ethers.provider.getBalance(buyerSigner.address);
    console.log({
        sellerBalance,
        buyerBalance
    });
    return {
        sellerBalance,
        buyerBalance
    }
}

const transferUsdt = async () => {
    const usdt = getContractData("usdt");
    const usdtContract = new BaseContract(usdt.address, usdt.abi, signers[0]) as AranDAOStableCoin;
    await usdtContract.transfer(buyerSigner.address, 1000 * 1e6);
}

const mintArcForSeller = async () => {
    const core = getContractData("core");
    const coreContract = new BaseContract(core.address, core.abi, signers[0]) as DNMCore;
    await coreContract.mintArc([sellerSigner.address], [parseEther('1')]);
}

const lockArcForSeller = async () => {
    const market = getContractData("market");
    const marketContract = new BaseContract(market.address, market.abi, sellerSigner) as DMarket;

    const arc = getContractData("arc");
    const arcContract = new BaseContract(arc.address, arc.abi, sellerSigner) as AssetRightsCoin;
    await arcContract.approve(market.address, parseEther('1'));

    await marketContract.lockSellerArc();
}

const createProduct = async () => {
    const market = getContractData("market");
    const marketContract = new BaseContract(market.address, market.abi, sellerSigner) as DMarket;

    await marketContract.createProduct(150 * 1e6, 50 * 1e6, 10, "QmeSP1oJm7dwmREyyZ6qupEStP76NyxLfRLhVFi9f5b1qU")
}

const purchaseOrder = async () => {
    const market = getContractData("market");
    const marketContract = new BaseContract(market.address, market.abi, buyerSigner) as DMarket;

    const usdt = getContractData("usdt");
    const usdtContract = new BaseContract(usdt.address, usdt.abi, buyerSigner) as AranDAOStableCoin;
    await usdtContract.approve(market.address, 403 * 1e6);

    await marketContract.purchaseProduct([{
        productId: 1,
        quantity: 2
    }], "0x8f9Bf8d2e866cd62F51a9Fa4831081db945eAfBa", 0);
}

const main = async () => {
    await clearEip7702Delegation(sellerSigner.address);
    await clearEip7702Delegation(buyerSigner.address);

    console.log("getEthBalance")
    await getEthBalance()
    console.log("transferUsdt")
    await transferUsdt()
    console.log("mintArcForSeller")
    await mintArcForSeller()
    console.log("lockArcForSeller")
    await lockArcForSeller()
    console.log("createProduct")
    await createProduct()
    console.log("purchaseOrder")
    await purchaseOrder()
    console.log("getEthBalance")
    await getEthBalance()
}

main();