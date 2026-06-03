import userData0001to1000 from "../deploy-utils/userData0001-1000.json";
import userData1001to2000 from "../deploy-utils/userData1001-2000.json";
import userData2001to3000 from "../deploy-utils/userData2001-3000.json";
import userData3001to4000 from "../deploy-utils/userData3001-4000.json";
import userData4001to5000 from "../deploy-utils/userData4001-5000.json";
import userData5001to6000 from "../deploy-utils/userData5001-6000.json";
import hre from "hardhat";
import { getContractData } from "../helpers/contractData.js";
import {
  AssetRightsCoin,
  DNMCore,
  FastValue,
} from "../types/ethers-contracts/index.js";
import { BaseContract } from "ethers";
const { ethers, networkHelpers } = await hre.network.create();
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

    const batchSize = 200;

    for (let i = 0; i < Math.ceil(allUserData.length / batchSize); i++) {
      const adaptedUserData = allUserData
        .slice(i * batchSize, Math.min((i + 1) * batchSize, allUserData.length))
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
      console.log(tx);
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

    const txMarket = await coreContract.addWhiteListContract(market.address);
    const txOrderbook = await coreContract.addWhiteListContract(
      orderbook.address,
    );
    return [txMarket, txOrderbook];
  },
  addManager: async () => {
    const core = getContractData("core");
    const coreContract = new BaseContract(
      core.address,
      core.abi,
      owner,
    ) as DNMCore;
    const managerAddress = "0x0000000000000000000000000000000000000000"; //TODO: Add address

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
    //TODO: Implement arc holders from CSV + Reserved saving in userData
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

    const months = [11, 12, 13, 14, 15, 16, 17, 18, 19];
    const totalShares = [0, 3, 1, 1, 2, 2, 2, 2, 2];
    const amounts = [
      1543000000, 3594400000, 571000000, 215260000, 433436000, 536832000,
      584100000, 0, 0,
    ];
    await fastValueContract.setTotalMonthlyFv(months, totalShares, amounts);
  },
  setUserMonthlyFv: async () => {
    const fastValue = getContractData("fastValue");
    const fastValueContract = new BaseContract(
      fastValue.address,
      fastValue.abi,
      owner,
    ) as FastValue;
  },
};
