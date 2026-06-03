import { BaseContract, BigNumberish, parseEther, parseUnits } from "ethers";
import { network } from "hardhat";

import {
  AranDAOBridge,
  DNMCore,
  DNMMintedProduct,
  AssetRightsCoin,
  DMarket,
  NftFundRaiseCollection,
} from "../types/ethers-contracts/index.js";
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
const fundraiseOwner = signers[1];
const farbod = signers[2];
const fourthSigner = signers[3];

const addMarketToMarketTokenMintOperators = async () => {
  const marketTokenContractData = getContractData("mintedProduct");
  const marketContractData = getContractData("market");
  const marketTokenContract = new BaseContract(
    marketTokenContractData.address,
    marketTokenContractData.abi,
    owner,
  ) as DNMMintedProduct;
  const tx = await marketTokenContract.setMintOperator(
    marketContractData.address,
  );
  console.log(tx.hash);
};

const setMarketAddresses = async () => {
  const marketContractData = getContractData("market");
  const marketTokenContractData = getContractData("mintedProduct");
  const daiContractData = getContractData("dai");
  const arcContractData = getContractData("arc");
  const coreContractData = getContractData("core");
  const marketContract = new BaseContract(
    marketContractData.address,
    marketContractData.abi,
    owner,
  ) as DMarket;

  try {
    const tx = await marketContract.setMarketTokenAddress(
      marketTokenContractData.address,
      daiContractData.address,
      arcContractData.address,
      coreContractData.address,
    );
    console.log(tx.hash);
  } catch (err: any) {
    console.log(parseError(marketContractData.abi, err.data));
    throw new Error("Error");
  }
};

const setFundraiseCollectionTransferAllowedAddresses = async () => {
  const orderBookContractData = getContractData("fundraiseMarket");
  const collectionContractData = getContractData("fundraiseToken");

  const collectionContract = new BaseContract(
    collectionContractData.address,
    collectionContractData.abi,
    owner,
  ) as NftFundRaiseCollection;

  const tx = await collectionContract.addTransferAllowedAddress(
    orderBookContractData.address,
  );
  console.log(tx.hash);
};

const setVaultAddressForCore = async () => {
  const coreContractData = getContractData("core");
  const vaultContractData = getContractData("vault");

  const coreContract = new BaseContract(
    coreContractData.address,
    coreContractData.abi,
    owner,
  ) as DNMCore;
  const tx = await coreContract.setVaultAddress(vaultContractData.address);
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
  const tx = await arcContract.setMintOperator(coreContractData.address, {
    gasPrice: ethers.parseUnits("70", "gwei"),
    nonce: 260,
  });
  console.log(tx.hash);
};

const transferArcToBridge = async () => {
  const arcContractData = getContractData("arc");
  const bridgeContractData = getContractData("bridge");

  const arcContract = new BaseContract(
    arcContractData.address,
    arcContractData.abi,
    owner,
  ) as AssetRightsCoin;

  try {
    const tx = await arcContract.transfer(
      bridgeContractData.address,
      parseEther("1100"),
    ); //TODO: Change to 1100
    console.log(tx.hash);
    //TODO: COmment
    // const sellerAddress = await fourthSigner.getAddress();
    // await arcContract.transfer(sellerAddress, parseEther('4'));

    // const farbodAddress = await farbodSigner.getAddress();
    // await arcContract.transfer(farbodAddress, parseEther('4'));
  } catch (e: any) {
    console.log(parseError(arcContractData.abi, e.data));
  }
};

const sleep = async (ts: number) => {
  return new Promise<void>((resolve) => {
    setTimeout(() => {
      resolve();
    }, 5000);
  });
};

const migrateUsers = async () => {
  const coreContractData = getContractData("core");
  const coreContract = new BaseContract(
    coreContractData.address,
    coreContractData.abi,
    owner,
  ) as DNMCore;

  for (let i = 50; i < Math.ceil(userData.length / 100); i++) {
    console.log(
      `Migrating user from ${i * 100} to ${Math.min(
        (i + 1) * 100,
        userData.length,
      )}`,
    );
    try {
      const tx = await coreContract.migrateUser(
        userData
          .slice(i * 100, Math.min((i + 1) * 100, userData.length))
          .map((user) => ({
            userAddr: user.userAddr,
            parentAddr: user.parentAddr,
            position: user.position,
            bv: user.bv,
            childrenSafeBv: user.childrenSafeBv as [
              BigNumberish,
              BigNumberish,
              BigNumberish,
              BigNumberish,
            ],
            childrenAggregateBv: user.childrenAggregateBv as [
              BigNumberish,
              BigNumberish,
              BigNumberish,
              BigNumberish,
            ],
            normalNodesBv: user.normalNodesBv as [BigNumberish, BigNumberish],
          })),
        {
          // gasPrice: parseUnits("60", "gwei"),
          // nonce: 252
        },
      );
      console.log("TX", tx.hash);
      await sleep(30000);
    } catch (err: any) {
      console.log(parseError(coreContractData.abi, err.data));
      break;
    }
  }
};

const getBridgeContract = () => {
  const bridgeContractData = getContractData("bridge");
  return {
    contract: new BaseContract(
      bridgeContractData.address,
      bridgeContractData.abi,
      owner,
    ) as AranDAOBridge,
    data: bridgeContractData,
  };
};

const addMarketToCoreOrderCreator = async () => {
  const coreContractData = getContractData("core");
  const marketContractData = getContractData("market");
  const fundraiseMarketContractData = getContractData("fundraiseMarket");

  const coreContract = new BaseContract(
    coreContractData.address,
    coreContractData.abi,
    owner,
  ) as DNMCore;
  const tx1 = await coreContract.addWhiteListedContract(
    marketContractData.address,
  );
  const tx2 = await coreContract.addWhiteListedContract(
    fundraiseMarketContractData.address,
  );

  console.log({ tx1, tx2 });
};

const addBridgeDNMSnapshot = async () => {
  const bridgeContract = getBridgeContract();
  for (let i = 0; i < Math.ceil(dnm.length / 100); i++) {
    console.log(
      `Importing DNM snapshots from ${i * 100} to ${Math.min(
        (i + 1) * 100,
        dnm.length,
      )}`,
    );
    try {
      let addresses: string[] = [];
      let amounts: string[] = [];
      dnm
        .slice(i * 100, Math.min((i + 1) * 100, dnm.length))
        .forEach((dnmAmount) => {
          addresses.push(dnmAmount.walletAddress);
          amounts.push(dnmAmount.dnmBalance);
        });

      const tx = await bridgeContract.contract.snapshotDnm(addresses, amounts);
      console.log(tx.hash);
      await sleep(10000);
    } catch (err: any) {
      console.log(parseError(bridgeContract.data.abi, err.data));
      break;
    }
  }
};

const addBridgeUVMSnapshot = async () => {
  const bridgeContract = getBridgeContract();
  for (let i = 0; i < Math.ceil(uvm.length / 100); i++) {
    console.log(
      `Importing UVM snapshots from ${i * 100} to ${Math.min(
        (i + 1) * 100,
        uvm.length,
      )}`,
    );
    try {
      let addresses: string[] = [];
      let amounts: string[] = [];
      uvm
        .slice(i * 100, Math.min((i + 1) * 100, uvm.length))
        .forEach((uvmAmount) => {
          addresses.push(uvmAmount.walletAddress);
          amounts.push(uvmAmount.uvmBalance);
        });

      const tx = await bridgeContract.contract.snapshotUvm(addresses, amounts);
      console.log(tx.hash);
      await sleep(10000);
    } catch (err: any) {
      console.log(parseError(bridgeContract.data.abi, err.data));
      break;
    }
  }
};

const addBridgeWrapperTokenSnapshot = async () => {
  const bridgeContract = getBridgeContract();
  for (let i = 0; i < Math.ceil(wrapperTokens.length / 100); i++) {
    console.log(
      `Importing Wrapper tokens snapshots from ${i * 100} to ${Math.min(
        (i + 1) * 100,
        wrapperTokens.length,
      )}`,
    );
    try {
      let addresses: string[] = [];
      let amounts: number[][] = [];
      wrapperTokens
        .slice(i * 100, Math.min((i + 1) * 100, wrapperTokens.length))
        .forEach((wrapperToken) => {
          addresses.push(wrapperToken.walletAddress);
          amounts.push(wrapperToken.tokenIds);
        });

      const tx = await bridgeContract.contract.snapshotWrapperToken(
        addresses,
        amounts,
      );
      console.log(tx.hash);
      await sleep(10000);
    } catch (err: any) {
      console.log(parseError(bridgeContract.data.abi, err.data)?.name);
      break;
    }
  }
};

const addBridgeStakeSnapshot = async () => {
  const bridgeContract = getBridgeContract();
  for (let i = 0; i < Math.ceil(stakes.length / 100); i++) {
    console.log(
      `Importing stakes snapshots from ${i * 100} to ${Math.min(
        (i + 1) * 100,
        stakes.length,
      )}`,
    );
    try {
      let stakeIds: number[] = [];
      let stakeValues: any[] = [];
      stakes
        .slice(i * 100, Math.min((i + 1) * 100, stakes.length))
        .forEach((stake) => {
          stakeIds.push(stake.id);
          stakeValues.push({
            userAddress: stake.userAddress,
            exists: stake.exists,
            totalPaidOut: stake.totalPaidOut,
            principleWithdrawn: stake.principleWithdrawn,
          });
        });

      const tx = await bridgeContract.contract.snapshotStake(
        stakeIds,
        stakeValues,
      );
      console.log(tx.hash);
      await sleep(10000);
    } catch (err: any) {
      console.log(parseError(bridgeContract.data.abi, err.data));
      break;
    }
  }
};

const finishSnapshotTaking = async () => {
  const bridgeContract = getBridgeContract();
  const tx = await bridgeContract.contract.finishSnapshotTaking();
  console.log(tx.hash);
};

const withdrawArcFromBridge = async () => {
  const bridgeContract = getBridgeContract();
  const tx = await bridgeContract.contract.withdrawRemainingArc(
    parseEther("2"),
  );
  console.log(tx.hash);
};

const main = async () => {
  // console.log("addMarketToMarketTokenMintOperators");
  // await addMarketToMarketTokenMintOperators();
  // console.log("setMarketAddresses");
  // await setMarketAddresses();
  // console.log("setFundraiseCollectionTransferAllowedAddresses");
  // await setFundraiseCollectionTransferAllowedAddresses();
  // console.log("setVaultAddressForCore");
  // await setVaultAddressForCore();
  // console.log("transferArcToBridge");
  // await transferArcToBridge();
  // console.log("withdrawArcFromBridge");
  // await withdrawArcFromBridge();
  // console.log("migrateUsers");
  // await migrateUsers();
  // // TODO: Bridge functions are not called yet
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
  // // Till here
  // console.log("addMarketToCoreOrderCreator");
  // await addMarketToCoreOrderCreator();
  console.log("addCoreAsARCMintOperator");
  await addCoreAsARCMintOperator();
  console.log("Done");
};

async function getNonce() {
  const tx = await ethers.provider.getTransaction(
    "0x2e30777e16979062a0636417e4b2e5574f723f98622009b6646f2c73ff3ec1f7",
  );
  console.log(tx?.nonce);
}

async function getBalance() {
  const balance = await ethers.provider.getBalance(signers[0]);
  console.log(balance);
}
getBalance();

10000.0;

// main();
// getNonce();
