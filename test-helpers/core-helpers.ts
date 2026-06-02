import type {
  HardhatEthers,
  HardhatEthersSigner,
} from "@nomicfoundation/hardhat-ethers/types";
import { AranDAOStableCoin, DNMCore } from "../types/ethers-contracts/index.js";

export function createCoreTestHelpers(
  ethers: HardhatEthers,
  signers: HardhatEthersSigner[],
) {
  const deployContracts = async () => {
    const arc = await ethers.deployContract("AssetRightsCoin");
    const arcAddress = await arc.getAddress();

    const usdt = await ethers.deployContract("AranDAOStableCoin", [
      signers[1].address,
      1000000 * 1e6,
    ]);
    const usdtAddress = await usdt.getAddress();

    const core = await ethers.deployContract("DNMCore", [
      signers[1].address,
      signers[0].address,
      arcAddress,
      usdtAddress,
    ]);
    const coreAddress = await core.getAddress();

    const fv = await ethers.deployContract("FastValue", [
      usdtAddress,
      coreAddress,
    ]);
    const fvAddress = await fv.getAddress();

    const twap = await ethers.deployContract("MockPriceFeed");
    const twapAddress = await twap.getAddress();

    const yieldPool = await ethers.deployContract("MockYieldPool", [
      usdtAddress,
    ]);
    const yieldPoolAddress = await yieldPool.getAddress();

    return {
      arc,
      arcAddress,
      usdt,
      usdtAddress,
      core,
      coreAddress,
      fv,
      fvAddress,
      twap,
      twapAddress,
      yieldPool,
      yieldPoolAddress,
    };
  };

  const mockPurchase = async (
    coreContract: DNMCore,
    usdtContract: AranDAOStableCoin,
    buyer: HardhatEthersSigner,
    bv: number,
    parentAddress: string,
    position: number,
  ) => {
    const coreAddress = await coreContract.getAddress();

    await usdtContract
      .connect(signers[1])
      .approve(coreAddress, bv * 1.01 * 1e6);

    await coreContract.connect(signers[1]).createOrder(
      buyer.address,
      parentAddress,
      position,
      [
        {
          sellerAddress: signers[9],
          bv: bv * 1e6,
          sv: 50 * 1e6,
        },
      ],
      bv * 1.01 * 1e6,
    );
  };

  const migrateUserDataMock: any = [
    {
      parentId: "0",
      userAddress: signers[0].address,
      position: "0",
      path: [],
      lastCalculatedOrder: "0",
      childrenBv: [
        "344900539999999999999720",
        "0",
        "0",
        "876382919999999999997264",
      ],
      childrenAggregateBv: [
        "344900539999999999999720",
        "0",
        "0",
        "876382919999999999997264",
      ],
      normalNodesBv: ["50539999999999999720", "455360919999999999997264"],
      bv: "0",
      eligibleArcWithdrawWeekNo: "26",
      superNodeTotalSteps: "73",
      bvOnBridgeTime: "0",
      fvEntranceMonth: "0",
      fvEntranceShare: "0",
      minBvForFv: "100000000",
      migrated: true,
      withdrawableCommission: "0",
      lastArcWithdrawNetworkerWeekNumber: "26",
      lastArcWithdrawUserWeekNumber: "0",
      createdAt: "1763758499",
      active: true,
    },
    {
      parentId: "1",
      userAddress: signers[1].address,
      position: "0",
      path: [
        "0x0100000000000000000000000000000000000000000000000000000000000000",
      ],
      lastCalculatedOrder: "0",
      childrenBv: [
        "239427839999999999999860",
        "0",
        "0",
        "34924000000000000000000",
      ],
      childrenAggregateBv: [
        "239427839999999999999860",
        "0",
        "0",
        "34924000000000000000000",
      ],
      normalNodesBv: ["174291839999999999999860", "346000000000000000000"],
      bv: "330500000000000000000",
      eligibleArcWithdrawWeekNo: "0",
      superNodeTotalSteps: "0",
      bvOnBridgeTime: "330500000000000000000",
      fvEntranceMonth: "0",
      fvEntranceShare: "0",
      minBvForFv: "100000000",
      migrated: true,
      withdrawableCommission: "0",
      lastArcWithdrawNetworkerWeekNumber: "0",
      lastArcWithdrawUserWeekNumber: "0",
      createdAt: "1763758499",
      active: true,
    },
  ];

  return { deployContracts, migrateUserDataMock, mockPurchase };
}
