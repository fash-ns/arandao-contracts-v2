import { BaseContract } from "ethers";
import { network } from "hardhat";

import {
  DNMCore,
  DNMMintedProduct,
  AssetRightsCoin,
  NftFundRaiseCollection,
} from "../types/ethers-contracts/index.js";
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
  const marketTokenContract = new BaseContract(
    marketTokenContractData.address,
    marketTokenContractData.abi,
    owner,
  ) as DNMMintedProduct;
  await marketTokenContract.setMintOperator(marketContractData.address);
};

const setFundraiseCollectionTransferAllowedAddresses = async () => {
  const orderBookContractData = getContractData("fundraiseOrderBook");
  const collectionContractData = getContractData("fundraiseCollection");

  const collectionContract = new BaseContract(
    collectionContractData.address,
    collectionContractData.abi,
    owner,
  ) as NftFundRaiseCollection;

  await collectionContract.addTransferAllowedAddress(
    orderBookContractData.address,
  );
};

const setVaultAddressForCore = async () => {
  const coreContractData = getContractData("core");
  const twapContractData = getContractData("twap");
  const yieldPoolContractData = getContractData("yieldPool");
  const fastValueContractData = getContractData("fastValue");

  const coreContract = new BaseContract(
    coreContractData.address,
    coreContractData.abi,
    owner,
  ) as DNMCore;
  const tx = await coreContract.setAddresses(
    twapContractData.address,
    yieldPoolContractData.address,
    fastValueContractData.address,
  );
  console.log(tx.hash);
};

const addCoreAsARCMintOperator = async () => {
  const arcContractData = getContractData("arc");
  const coreContractData = getContractData("core");

  const arcContract = new BaseContract(
    arcContractData.address,
    arcContractData.abi,
    owner,
  ) as AssetRightsCoin;
  await arcContract.setMintOperator(coreContractData.address);
};

const sleep = async (ts: number) => {
  return new Promise<void>((resolve) => {
    setTimeout(() => {
      resolve();
    }, 5000);
  });
};

// const migrateUsers = async () => {
//     const coreContractData = getContractData("core");
//     const coreContract = new BaseContract(coreContractData.address, coreContractData.abi, owner) as DNMCore;

//     for (let i = 20; i < Math.ceil(userData.length / 100); i++) {
//         console.log(`Migrating user from ${i * 100} to ${Math.min((i + 1) * 100, userData.length)}`)
//         try {
//             const tx = await coreContract.migrateUser(userData.slice(i * 100, Math.min((i + 1) * 100, userData.length)).map(user => ({
//                 userAddr: user.userAddr,
//                 parentAddr: user.parentAddr,
//                 position: user.position,
//                 bv: user.bv,
//                 childrenSafeBv: user.childrenSafeBv as [BigNumberish, BigNumberish, BigNumberish, BigNumberish],
//                 childrenAggregateBv: user.childrenAggregateBv as [BigNumberish, BigNumberish, BigNumberish, BigNumberish],
//                 normalNodesBv: user.normalNodesBv as [BigNumberish, BigNumberish]
//             })), {gasPrice: parseUnits("120", "gwei")});
//             console.log("TX", tx.hash);
//             await sleep(10000);
//         } catch (err: any) {
//             console.log(parseError(coreContractData.abi, err.data));
//             break;
//         }
//     }
// }

const addMarketToCoreOrderCreator = async () => {
  const coreContractData = getContractData("core");
  const marketContractData = getContractData("market");
  const fundraiseCollectionContractData = getContractData("fundraiseOrderBook");

  const coreContract = new BaseContract(
    coreContractData.address,
    coreContractData.abi,
    owner,
  ) as DNMCore;
  await coreContract.addWhiteListContract(marketContractData.address);
  await coreContract.addWhiteListContract(
    fundraiseCollectionContractData.address,
  );
};

const main = async () => {
  console.log("addMarketToMarketTokenMintOperators");
  await addMarketToMarketTokenMintOperators();
  console.log("setFundraiseCollectionTransferAllowedAddresses");
  await setFundraiseCollectionTransferAllowedAddresses();
  console.log("setVaultAddressForCore");
  await setVaultAddressForCore();
  console.log("transferArcToBridge");
  console.log("addMarketToCoreOrderCreator");
  await addMarketToCoreOrderCreator();
  console.log("addCoreAsARCMintOperator");
  await addCoreAsARCMintOperator();
  console.log("Done");
};

main();
