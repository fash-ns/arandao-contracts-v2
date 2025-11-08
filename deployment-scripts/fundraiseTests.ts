import { network } from "hardhat";
import { BaseContract, parseEther } from "ethers";
import { getContractData } from "../helpers/contractData.js";
import { NftFundRaiseCollection, NFTFundRaiseOrderBook, UVM } from "../types/ethers-contracts/index.js";
import { parseError } from "./utils.js";
const { ethers } = await network.connect();

const signers = await ethers.getSigners();
const contractOwner = signers[0];       //0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266
const sellerSigner = signers[1];        //0x5582996842e06d2ef7Cf332d678b85f102Df3D1e
const buyerSigner = signers[2];         //0xdFa0C8A616025b1621ADcC52183031E94C6f1C51
const thirdSigner = signers[3];         //0xf8499823A84162aAc6646f63c296e5D1f8088ab5
const farbodSigner = signers[4];        //0x5E642CA96e24eB5A0e80ca45C6221d8410e3916C
const newSigner = signers[5];           //0xC4ad083BB6606A72563A792E7219744693f260ec
const daiHolderSigner = signers[6];     //0x9DB3937aE12adf8ADbE18035C2dE7d77c4d2242B

const transferDai = async () => {
    const daiContractData = getContractData("dai");

    const daiContract = new BaseContract(daiContractData.address, daiContractData.abi, farbodSigner) as UVM;
    const polContract = new BaseContract("0x0000000000000000000000000000000000001010", daiContractData.abi, farbodSigner) as UVM;
    const buyerAddr = await buyerSigner.getAddress();
    const ownerAddr = await contractOwner.getAddress();
    const thirdAddr = await thirdSigner.getAddress();
    const newAddr = await newSigner.getAddress();

    await contractOwner.sendTransaction({
        to: buyerSigner,
        value: parseEther("1")
      });
    await contractOwner.sendTransaction({
        to: newSigner,
        value: parseEther("1")
      });

    // await daiContract.transfer(buyerAddr, parseEther('100'));
    // await daiContract.transfer(ownerAddr, parseEther('100'));
    // await daiContract.transfer(thirdAddr, parseEther('100'));
    // await daiContract.transfer(newAddr, parseEther('100'));

    await polContract.transfer(ownerAddr, parseEther('1'));
    await polContract.transfer(newAddr, parseEther('1'));
    await polContract.transfer(buyerAddr, parseEther('1'));
}

const mint2000Nft = async () => {
    const collectionContractData = getContractData("fundraiseToken");
    const collectionContract = new BaseContract(collectionContractData.address, collectionContractData.abi, contractOwner) as NftFundRaiseCollection;

    const receiverAddr = await farbodSigner.getAddress();

    for (let i = 0; i < 40; i++) {
        const tokenIds = new Array(50).fill(0).map((_, index) => (i * 50) + index + 1);
        const editions = new Array(50).fill(0).map(() => 1);
        const uris = new Array(50).fill("").map(() => "QmbWqxBEKC3P8tqsKc98xmWNzrzDtRLMiMPL8wBuTGsMnR");
        await collectionContract.batchTokenMint(receiverAddr, tokenIds, editions);
    }
}

const transferOwnership = async () => {
    const collectionContractData = getContractData("fundraiseToken");
    const collectionContract = new BaseContract(collectionContractData.address, collectionContractData.abi, contractOwner) as NftFundRaiseCollection;

    const farbodAddr = await farbodSigner.getAddress();

    await collectionContract.transferOwnership(farbodAddr);

}

const disableInitialMint = async () => {
    const collectionContractData = getContractData("fundraiseToken");
    const collectionContract = new BaseContract(collectionContractData.address, collectionContractData.abi, contractOwner) as NftFundRaiseCollection;

    await collectionContract.disableInitialMint();
}

const getOwnerOf = async (addr: string, id: number) => {
    const collectionContractData = getContractData("fundraiseToken");
    const collectionContract = new BaseContract(collectionContractData.address, collectionContractData.abi, contractOwner) as NftFundRaiseCollection;

    const owner = await collectionContract.balanceOf(addr, id);
    console.log(owner);
}

const transferCollectionToken = async () => {
    const collectionContractData = getContractData("fundraiseToken");
    const collectionContract = new BaseContract(collectionContractData.address, collectionContractData.abi, farbodSigner) as NftFundRaiseCollection;

    const fromAddr = await farbodSigner.getAddress();
    const toAddr = await buyerSigner.getAddress();


    try {
        await collectionContract.safeTransferFrom(fromAddr, toAddr, 1, 1, "0x");
    } catch (err: any) {
        console.log(parseError(collectionContractData.abi, err.data));
    }
}

const listTokenForSale = async () => {
    const orderBookContractData = getContractData("fundraiseMarket");
    const collectionContractData = getContractData("fundraiseToken");

    const orderBookContract = new BaseContract(orderBookContractData.address, orderBookContractData.abi, buyerSigner) as NFTFundRaiseOrderBook;
    const collectionContract = new BaseContract(collectionContractData.address, collectionContractData.abi, buyerSigner) as NftFundRaiseCollection;

    await collectionContract.setApprovalForAll(orderBookContractData.address, true);

    try {
        await orderBookContract.listTokenForSale(1, parseEther('100'), 1);
    } catch(err: any) {
        // console.log(err);
        console.log(parseError(collectionContractData.abi, err.data));
    }
}

const collectListing = async () => { //+14.6
    const orderBookContractData = getContractData("fundraiseMarket");
    const coreContractData = getContractData("core");
    const daiContractData = getContractData("dai");

    const daiContract = new BaseContract(daiContractData.address, daiContractData.abi, farbodSigner) as UVM;
    const orderBookContract = new BaseContract(orderBookContractData.address, orderBookContractData.abi, farbodSigner) as NFTFundRaiseOrderBook;

    await daiContract.approve(orderBookContractData.address, parseEther('100000'));

    try {
        await orderBookContract.buyListing(1, 1, "0x50FBc531a4b37fB912A379B310720441f58e5A56", 0);
    } catch (err: any) {
        console.log(parseError(coreContractData.abi, err.data));
    }
}

const cancelListing = async () => {
    const orderBookContractData = getContractData("fundraiseMarket");
    const orderBookContract = new BaseContract(orderBookContractData.address, orderBookContractData.abi, farbodSigner) as NFTFundRaiseOrderBook;

    try {
        await orderBookContract.cancelListForSale(2);
    } catch (err: any) {
        console.log(parseError(orderBookContractData.abi, err.data));
    }
}

const placeOffer = async () => {
    const orderBookContractData = getContractData("fundraiseMarket");
    const daiContractData = getContractData("dai");
    
    const orderBookContract = new BaseContract(orderBookContractData.address, orderBookContractData.abi, farbodSigner) as NFTFundRaiseOrderBook;
    const daiContract = new BaseContract(daiContractData.address, daiContractData.abi, farbodSigner) as UVM;

    await daiContract.approve(orderBookContractData.address, parseEther('100'));

    try {
        await orderBookContract.placeOffer(1, 1, parseEther('100'), "0x50FBc531a4b37fB912A379B310720441f58e5A56", 3);
    } catch (err: any) {
        console.log(parseError(orderBookContractData.abi, err.data));
    }
}

const acceptOffer = async () => { //+16.8 BV
    const orderBookContractData = getContractData("fundraiseMarket");
    const collectionContractData = getContractData("fundraiseToken");

    const orderBookContract = new BaseContract(orderBookContractData.address, orderBookContractData.abi, farbodSigner) as NFTFundRaiseOrderBook;
    const collectionContract = new BaseContract(collectionContractData.address, collectionContractData.abi, farbodSigner) as NftFundRaiseCollection;

    await collectionContract.setApprovalForAll(orderBookContractData.address, true);

    try {
        await orderBookContract.acceptOffer(1, 1);
    } catch (err: any) {
        console.log(parseError(collectionContractData.abi, err.data));
    }
}

const cancelOffer = async () => {
    const orderBookContractData = getContractData("fundraiseMarket");
    const collectionContractData = getContractData("fundraiseToken");

    const orderBookContract = new BaseContract(orderBookContractData.address, orderBookContractData.abi, buyerSigner) as NFTFundRaiseOrderBook;
    const collectionContract = new BaseContract(collectionContractData.address, collectionContractData.abi, buyerSigner) as NftFundRaiseCollection;

    await collectionContract.setApprovalForAll(orderBookContractData.address, true);

    try {
        await orderBookContract.cancelOffer(2);
    } catch (err: any) {
        console.log(parseError(orderBookContractData.abi, err.data));
    }
}

const getDaiBalances = async () => {
    const daiContractData = getContractData("dai");
    const daiContract = new BaseContract(daiContractData.address, daiContractData.abi, farbodSigner) as UVM;

    for (let i = 0; i < signers.length; i++) {
        const addr = await signers[i].getAddress();
        const balance = await daiContract.balanceOf(addr);
        console.log({addr, balance})
    }
}

const createRound = async () => {
    const collectionContractData = getContractData("fundraiseToken");
    const collectionContract = new BaseContract(collectionContractData.address, collectionContractData.abi, contractOwner) as NftFundRaiseCollection;

    try {
        await collectionContract.addClaimRound(1761917431, parseEther('22'));
    } catch (err: any) {
        console.log(parseError(collectionContractData.abi, err.data));
    }
}

const claimFromRound = async () => {
    const collectionContractData = getContractData("fundraiseToken");
    const daiContractData = getContractData("dai");
    
    const collectionContract = new BaseContract(collectionContractData.address, collectionContractData.abi, buyerSigner) as NftFundRaiseCollection;
    const daiContract = new BaseContract(daiContractData.address, daiContractData.abi, buyerSigner) as UVM;

    await daiContract.approve(collectionContractData.address, parseEther('44'));

    try {
        await collectionContract.claimTokens(3, 2);
    } catch (err: any) {
        console.log(parseError(collectionContractData.abi, err.data));
    }

}

const claimTokensByOwner = async () => {
    const collectionContractData = getContractData("fundraiseToken");
    const collectionContract = new BaseContract(collectionContractData.address, collectionContractData.abi, contractOwner) as NftFundRaiseCollection;

    try {
        await collectionContract.batchOwnerClaim(1, new Array(500).fill(0).map((_, index) => index + 1));
    } catch (err: any) {
        console.log(parseError(collectionContractData.abi, err.data));
    }
}

const main = async () => {
    // await mint2000Nft();
    // await disableInitialMint();
    // await transferDai();
    // await transferOwnership();
    // await transferCollectionToken();
    // await getOwnerOf('0x5E642CA96e24eB5A0e80ca45C6221d8410e3916C', 2002);
    // await listTokenForSale();
    // await collectListing();
    // await cancelListing();
    // await placeOffer();
    await acceptOffer();
    // await cancelOffer();
    // await getDaiBalances();
    // await createRound();
    // await claimFromRound();
    // await claimTokensByOwner();
}

main();