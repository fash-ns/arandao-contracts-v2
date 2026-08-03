import userData0001to1000 from "../deploy-utils/userData0001-1000.json";
import userData1001to2000 from "../deploy-utils/userData1001-2000.json";
import userData2001to3000 from "../deploy-utils/userData2001-3000.json";
import userData3001to4000 from "../deploy-utils/userData3001-4000.json";
import userData4001to5000 from "../deploy-utils/userData4001-5000.json";
import userData5001to6000 from "../deploy-utils/userData5001-6000.json";
import arcShares from "../deploy-utils/adaptedShares.json";
import fundraiseShares from "../deploy-utils/adaptedFundraiseShares.json";
import fastValueUsers from "../deploy-utils/normalizedFastValueUsers.json"
import fastValueUserShares from "../deploy-utils/normalizedFastValueUserShares.json"

import hre from "hardhat";
import { getContractData } from "../helpers/contractData.js";
import {
  AssetRightsCoin,
  DNMCore,
  DNMMintedProduct,
  FastValue,
  NftFundRaiseCollection,
  YieldPool,
} from "../types/ethers-contracts/index.js";
import { BaseContract, parseEther } from "ethers";
const { ethers } = await hre.network.create();
const signers = await ethers.getSigners();

const owner = signers[0];

const allUserData = [
  ...userData0001to1000,
  ...userData1001to2000,
  ...userData2001to3000,
  ...userData3001to4000,
  ...userData4001to5000,
  ...userData5001to6000,
];

/* 00 parentId */
/* 01 userAddress */
/* 02 position */
/* 03 path */
/* 04 lastCalculatedOrder */
/* 05 childrenBv */
/* 06 childrenAggregateBv */
/* 07 normalNodesBv */
/* 08 bv */
/* 09 eligibleDnmWithdrawWeekNo */
/* 10 superNodeTotalSteps */
/* 11 bvOnBridgeTime */
/* 12 fvEntranceMonth */
/* 13 fvEntranceShare */
/* 14 networkerDnmShare */
/* 15 withdrawNetworkerDnmShareMonth */
/* 16 migrated */
/* 17 withdrawableCommission */
/* 18 lastDnmWithdrawNetworkerWeekNumber */
/* 19 lastDnmWithdrawUserWeekNumber */
/* 20 createdAt */
/* 21 active */

const sleep = (ts: number) => new Promise<void>(resolve => {
  setTimeout(() => {
    resolve();
  }, ts)
})

const Arc = {
  setCoreAsMintOperator: async () => {
    const arc = getContractData("arc");
    const core = getContractData("core");
    const arcContract = new ethers.BaseContract(
      arc.address,
      arc.abi,
      owner,
    ) as AssetRightsCoin;
    const tx = await arcContract.setMintOperator(core.address);
    return tx;
  },
  approveYieldPoolToSpendArc: async () => {
    const arc = getContractData("arc");
    const yieldPool = getContractData("yieldPool");
    const arcContract = new ethers.BaseContract(
      arc.address,
      arc.abi,
      owner,
    ) as AssetRightsCoin;

    const totalArcSupp = arcShares
      .map((share) => share.arcShare)
      .reduce((prev, current) => {
        return BigInt(prev) + BigInt(current);
      }, 0n);

    const tx = await arcContract.approve(yieldPool.address, totalArcSupp);
    return tx;
  },
  revokeDevMode: async () => {
    const arc = getContractData("arc");
    const arcContract = new ethers.BaseContract(
      arc.address,
      arc.abi,
      owner,
    ) as AssetRightsCoin;
    const tx = await arcContract.revokeDeployer();
    return tx;
  },
};

const Core = {
  migrateUsers: async () => {
    const core = getContractData("core");
    const coreContract = new BaseContract(
      core.address,
      core.abi,
      owner,
    ) as DNMCore;

    const batchSize = 40;
    const init = 124;
    for (let i = init; i < Math.ceil(allUserData.length / batchSize); i++) {
      const from = i * batchSize;
      const to = Math.min((i + 1) * batchSize, allUserData.length)
      console.log(`Batch #${i}: (${from} - ${to})`);
      await sleep(1000);
      const adaptedUserData = allUserData
        .slice(from, to)
        .map((i) => ({
          parentId: i.data[0],
          userAddress: i.data[1],
          position: i.data[2],
          path: i.data[3],
          lastCalculatedOrder: 0,
          childrenBv: [
            BigInt((i.data[5] as string[])[0]) / BigInt("1000000000000"),
            BigInt((i.data[5] as string[])[1]) / BigInt("1000000000000"),
            BigInt((i.data[5] as string[])[2]) / BigInt("1000000000000"),
            BigInt((i.data[5] as string[])[3]) / BigInt("1000000000000"),
          ],
          childrenAggregateBv: [
            BigInt((i.data[6] as string[])[0]) / BigInt("1000000000000"),
            BigInt((i.data[6] as string[])[1]) / BigInt("1000000000000"),
            BigInt((i.data[6] as string[])[2]) / BigInt("1000000000000"),
            BigInt((i.data[6] as string[])[3]) / BigInt("1000000000000"),
          ],
          normalNodesBv: [
            BigInt((i.data[7] as string[])[0]) / BigInt("1000000000000"),
            BigInt((i.data[7] as string[])[1]) / BigInt("1000000000000"),
          ],
          bv: BigInt(i.data[8] as string) / BigInt("1000000000000"),
          eligibleArcWithdrawWeekNo: i.data[9],
          superNodeTotalSteps: i.data[10],
          bvOnBridgeTime:
            BigInt(i.data[11] as string) / BigInt("1000000000000"),
          fvEntranceMonth: i.data[12],
          fvEntranceShare: i.data[13],
          minBvForFv: BigInt("100000000"),
          migrated: i.data[16],
          withdrawableCommission: i.data[17],
          lastArcWithdrawNetworkerWeekNumber: i.data[18],
          lastArcWithdrawUserWeekNumber: i.data[19],
          createdAt: i.data[20],
          active: true,
        }));

      const tx = await coreContract.migrateUser(adaptedUserData as any);
      console.log(tx.hash);
      console.log("Waiting one block for confirmation ...");
      await tx.wait(1);
      console.log("Block confirmation succeed. Waiting 5 seconds to go for next batch ...");
      await sleep(5000);
    }
  },
  setMarketAsWhiteListContract: async () => {
    const core = getContractData("core");
    const market = getContractData("market");
    const orderbook = getContractData("fundraiseOrderBook");
    const coreContract = new BaseContract(
      core.address,
      core.abi,
      owner,
    ) as DNMCore;

    // const txMarket = await coreContract.addWhiteListContract(market.address);
    const txOrderbook = await coreContract.addWhiteListContract(
      orderbook.address,
    );
    console.log(txOrderbook.hash);
    return [txOrderbook];
  },
  addManager: async () => {
    const core = getContractData("core");
    const coreContract = new BaseContract(
      core.address,
      core.abi,
      owner,
    ) as DNMCore;
    const managerAddress = "0xbb46E467B96f8DB92E7DE0F147313489A77ba8D1";

    const tx = await coreContract.addManager(managerAddress);
    return tx;
  },
  setAddresses: async () => {
    const core = getContractData("core");
    const priceFeed = getContractData("twap");
    const fastValue = getContractData("fastValue");
    const yieldPool = getContractData("yieldPool");
    const coreContract = new BaseContract(
      core.address,
      core.abi,
      owner,
    ) as DNMCore;

    const tx = await coreContract.setAddresses(
      priceFeed.address,
      yieldPool.address,
      fastValue.address,
    );

    return tx;
  },
  mintArcs: async () => {
    const core = getContractData("core");
    const coreContract = new BaseContract(
      core.address,
      core.abi,
      owner,
    ) as DNMCore;

    const totalArcSupp = arcShares
      .map((share) => share.arcShare)
      .reduce((prev, current) => {
        return BigInt(prev) + BigInt(current);
      }, 0n);

    const additionalValue = parseEther('240');

    const ownerAddress = await owner.getAddress();

    const tx = await coreContract.mintArc(
      [ownerAddress, "0x5AF0B1c446D5b47b62034364AF0ded332e1d5210"],
      [totalArcSupp, additionalValue],
    );
    return tx;
  },
  revokeDevMode: async () => {
    const core = getContractData("core");
    const coreContract = new BaseContract(
      core.address,
      core.abi,
      owner,
    ) as DNMCore;

    const tx = await coreContract.revokeDevMode();
    return tx;
  },
};

const FastValue = {
  setTotalMonthlyFv: async () => {
    const fastValue = getContractData("fastValue");
    const fastValueContract = new BaseContract(
      fastValue.address,
      fastValue.abi,
      owner,
    ) as FastValue;

    const months = [11, 12, 13, 14, 15, 16, 17, 18, 19, 20, 21, 22, 23];
    const totalShares = [0, 3, 1, 1, 2, 2, 2, 34, 39, 8, 6, 2, 2];
    const amounts = [
      1543000000, 3594400000, 571000000, 215260000, 433436000, 536832000,
      584100000, 10422000000, 2950540000, 0, 0, 0, 0
    ];
    const tx = await fastValueContract.setTotalMonthlyFv(
      months,
      totalShares,
      amounts,
    );
    return tx;
  },
  setUserMonthlyFv: async () => {
    const fastValue = getContractData("fastValue");
    const fastValueContract = new BaseContract(
      fastValue.address,
      fastValue.abi,
      owner,
    ) as FastValue;

    let fvLength = fastValueUsers.length;

    for (let i = 0; i < fvLength; i++) {
      const user = fastValueUsers[i];
      console.log(`#${i} Setting user with id ${user.userId}`);
      const tx = await fastValueContract.setUserMonthlyFv(
        user.userId,
        user.months,
        user.shares,
        user.isWithdrawn
      )

      await tx.wait();
      console.log(tx.hash);
      await sleep(5000);
    }
  },
  setUserEntranceFvShare: async () => {
    const fastValue = getContractData("fastValue");
    const fastValueContract = new BaseContract(
      fastValue.address,
      fastValue.abi,
      owner,
    ) as FastValue;

    const userIds = [];
    const shares = [];

    for (const share of fastValueUserShares) {
      userIds.push(share.userId);
      shares.push(share.share);
    }

    const tx = await fastValueContract.setUserEntranceShares(
      userIds,
      shares,
    )

    return tx;
  },

  revokeDevMode: async () => {
    const fastValue = getContractData("fastValue");
    const fastValueContract = new BaseContract(
      fastValue.address,
      fastValue.abi,
      owner,
    ) as FastValue;

    const tx = await fastValueContract.revokeDevMode();
    return [tx];
  },
};

const YieldPool = {
  batchStake: async () => {
    const yieldPool = getContractData("yieldPool");
    const yieldPoolContract = new BaseContract(
      yieldPool.address,
      yieldPool.abi,
      owner,
    ) as YieldPool;

    const batchSize = 105;

    for (let i = 0; i < Math.ceil(arcShares.length / batchSize); i++) {
      const shareWalletAddresses = arcShares
        .slice(i * batchSize, Math.min((i + 1) * batchSize, arcShares.length))
        .map((share) => share.walletAddress);
      const shareAmounts = arcShares
        .slice(i * batchSize, Math.min((i + 1) * batchSize, arcShares.length))
        .map((share) => share.arcShare);

      const tx = await yieldPoolContract.batchStakeFor(
        shareWalletAddresses,
        shareAmounts,
      );
      console.log(tx);
      await sleep(15000);
    }
  },
};

const MarketToken = {
  setMarketAsMintOperator: async () => {
    const marketToken = getContractData("mintedProduct");
    const market = getContractData("market");
    const marketTokenContract = new BaseContract(
      marketToken.address,
      marketToken.abi,
      owner,
    ) as DNMMintedProduct;

    const tx = await marketTokenContract.setMintOperator(market.address);
    return tx;
  },

  revokeDevMode: async () => {
    const marketToken = getContractData("mintedProduct");
    const marketTokenContract = new BaseContract(
      marketToken.address,
      marketToken.abi,
      owner,
    ) as DNMMintedProduct;

    const tx = await marketTokenContract.revokeDeployer();
    return tx;
  },
};

const FundRaise = {
  setOrderBookAsTransferAllowed: async () => {
    const fundraiseCollection = getContractData("fundraiseCollection");
    const fundraiseOrderbook = getContractData("fundraiseOrderBook");

    const collectionContract = new BaseContract(fundraiseCollection.address, fundraiseCollection.abi, owner) as NftFundRaiseCollection;
    const tx = await collectionContract.addTransferAllowedAddress(fundraiseOrderbook.address);
    return tx;
  },
  mintFundraiseTokens: async () => {
    console.log(fundraiseShares.length);
    const fundraiseCollection = getContractData("fundraiseCollection");
    const collectionContract = new BaseContract(fundraiseCollection.address, fundraiseCollection.abi, owner) as NftFundRaiseCollection;

    const length = fundraiseShares.length;
    let seq = 74;

    while (seq < length) {
      const share = fundraiseShares[seq];
      console.log(`#${seq} Minting tokens for ${share.wallerAddress}`);
      await sleep(1000);
      const tx = await collectionContract.batchTokenMint(share.wallerAddress, share.tokenIds, share.editions);
      console.log(tx.hash);
      console.log("Wating for block confirmation ...");
      await tx.wait();
      console.log("Confirmed. Waiting 10 seconds to continue ...");
      await sleep(7000);
      seq += 1;
    }
  },
  revokeDevMode: async () => {
    const fundraiseCollection = getContractData("fundraiseCollection");

    const collectionContract = new BaseContract(fundraiseCollection.address, fundraiseCollection.abi, owner) as NftFundRaiseCollection;
    const tx = await collectionContract.renounceDeployer();
    return tx;
  },
}

const main = async () => {
  // console.log("Arc.setCoreAsMintOperator");
  // console.log((await Arc.setCoreAsMintOperator()).hash);
  // console.log("Arc.approveYieldPoolToSpendArc");
  // console.log((await Arc.approveYieldPoolToSpendArc()).hash);
  //! console.log("Arc.revokeDevMode");
  //! await Arc.revokeDevMode();

  // console.log("Core.migrateUsers");
  // await Core.migrateUsers();
  // console.log("Core.setMarketAsWhiteListContract");
  // await Core.setMarketAsWhiteListContract();
  // console.log("Core.addManager");
  // await Core.addManager();
  // console.log("Core.setAddresses");
  // console.log((await Core.setAddresses()).hash);
  // console.log("Core.mintArcs");
  // console.log((await Core.mintArcs()).hash);
  //! console.log("Core.revokeDevMode");
  //! await Core.revokeDevMode();

  // console.log("FastValue.setTotalMonthlyFv");
  // console.log((await FastValue.setTotalMonthlyFv()).hash);
  // console.log("FastValue.setUserMonthlyFv");
  // await FastValue.setUserMonthlyFv();
  console.log("FastValue.setUserEntranceFvShare");
  console.log((await FastValue.setUserEntranceFvShare()).hash);
  //! console.log("FastValue.revokeDevMode");
  //! await FastValue.revokeDevMode();

  // console.log("YieldPool.batchStake");
  // await YieldPool.batchStake();

  // console.log("MarketToken.setMarketAsMintOperator");
  // console.log((await MarketToken.setMarketAsMintOperator()).hash);
  //! console.log("MarketToken.revokeDevMode");
  //! await MarketToken.revokeDevMode();

  // console.log('FundRaise.setOrderBookAsTransferAllowed');
  // console.log((await FundRaise.setOrderBookAsTransferAllowed()).hash);
  // console.log('FundRaise.mintFundraiseTokens');
  // await FundRaise.mintFundraiseTokens();
  //! console.log('FundRaise.revokeDevMode');
  //! await FundRaise.revokeDevMode();
};

main();
