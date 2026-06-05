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
        "344900539999",
        "0",
        "0",
        "876382919999",
      ],
      childrenAggregateBv: [
        "344900539999",
        "0",
        "0",
        "876382919999",
      ],
      normalNodesBv: ["50539999", "455360919999"],
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
        "239427839999",
        "0",
        "0",
        "34924000000",
      ],
      childrenAggregateBv: [
        "239427839999",
        "0",
        "0",
        "34924000000",
      ],
      normalNodesBv: ["174291839999", "346000000"],
      bv: "330500000",
      eligibleArcWithdrawWeekNo: "0",
      superNodeTotalSteps: "0",
      bvOnBridgeTime: "330500000",
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
    {
      parentId: "2",
      userAddress: signers[2].address,
      position: "0",
      path: ["0x0101000000000000000000000000000000000000000000000000000000000000"],
      lastCalculatedOrder: "0",
      childrenBv: ["198542140000", "0", "0", "0"],
      childrenAggregateBv: ["198542140000", "0", "0", "0"],
      normalNodesBv: ["198542140000", "0"],
      bv: "66000000",
      eligibleArcWithdrawWeekNo: "0",
      superNodeTotalSteps: "0",
      bvOnBridgeTime: "66000000",
      fvEntranceMonth: "0",
      fvEntranceShare: "0",
      minBvForFv: "0",
      migrated: true,
      withdrawableCommission: "0",
      lastArcWithdrawNetworkerWeekNumber: "0",
      lastArcWithdrawUserWeekNumber: "0",
      createdAt: "1763758499",
      active: true
    },
    {
      parentId: "3",
      userAddress: signers[3].address,
      position: "0",
      path: ["0x0101010000000000000000000000000000000000000000000000000000000000"],
      lastCalculatedOrder: "0",
      childrenBv: ["198476140000", "0", "0", "0"],
      childrenAggregateBv: ["198476140000", "0", "0", "0"],
      normalNodesBv: ["198476140000", "0"],
      bv: "66000000",
      eligibleArcWithdrawWeekNo: "0",
      superNodeTotalSteps: "0",
      bvOnBridgeTime: "66000000",
      fvEntranceMonth: "0",
      fvEntranceShare: "0",
      minBvForFv: "0",
      migrated: true,
      withdrawableCommission: "0",
      lastArcWithdrawNetworkerWeekNumber: "0",
      lastArcWithdrawUserWeekNumber: "0",
      createdAt: "1763758499",
      active: true
    },
    {
      parentId: "4",
      userAddress: signers[4].address,
      position: "0",
      path: ["0x0101010100000000000000000000000000000000000000000000000000000000"],
      lastCalculatedOrder: "0",
      childrenBv: ["198410140000", "0", "0", "0"],
      childrenAggregateBv: ["198410140000", "0", "0", "0"],
      normalNodesBv: ["198410140000", "0"],
      bv: "66000000",
      eligibleArcWithdrawWeekNo: "0",
      superNodeTotalSteps: "0",
      bvOnBridgeTime: "66000000",
      fvEntranceMonth: "0",
      fvEntranceShare: "0",
      minBvForFv: "0",
      migrated: true,
      withdrawableCommission: "0",
      lastArcWithdrawNetworkerWeekNumber: "0",
      lastArcWithdrawUserWeekNumber: "0",
      createdAt: "1763758499",
      active: true
    },
    {
      parentId: "5",
      userAddress: signers[5].address,
      position: "0",
      path: ["0x0101010101000000000000000000000000000000000000000000000000000000"],
      lastCalculatedOrder: "0",
      childrenBv: ["195545640000", "0", "0", "2690000000"],
      childrenAggregateBv: ["195545640000", "0", "0", "2690000000"],
      normalNodesBv: ["193045640000", "190000000"],
      bv: "66000000",
      eligibleArcWithdrawWeekNo: "6",
      superNodeTotalSteps: "5",
      bvOnBridgeTime: "66000000",
      fvEntranceMonth: "0",
      fvEntranceShare: "0",
      minBvForFv: "1",
      migrated: true,
      withdrawableCommission: "0",
      lastArcWithdrawNetworkerWeekNumber: "6",
      lastArcWithdrawUserWeekNumber: "0",
      createdAt: "1763758499",
      active: true
    },
    {
      parentId: "6",
      userAddress: signers[6].address,
      position: "3",
      path: ["0x0101010101040000000000000000000000000000000000000000000000000000"],
      lastCalculatedOrder: "0",
      childrenBv: ["565000000", "0", "0", "1925000000"],
      childrenAggregateBv: ["565000000", "0", "0", "1925000000"],
      normalNodesBv: ["65000000", "1425000000"],
      bv: "200000000",
      eligibleArcWithdrawWeekNo: "6",
      superNodeTotalSteps: "1",
      bvOnBridgeTime: "0",
      fvEntranceMonth: "0",
      fvEntranceShare: "0",
      minBvForFv: "100000000",
      migrated: true,
      withdrawableCommission: "0",
      lastArcWithdrawNetworkerWeekNumber: "6",
      lastArcWithdrawUserWeekNumber: "3",
      createdAt: "1763758499",
      active: true
    },
  //   {
  //     parentId: "7",
  //     userAddress: signers[7].address,
  //     position: "3",
  //     path: ["0x0101010101040400000000000000000000000000000000000000000000000000"],
  //     lastCalculatedOrder: "0",
  //     childrenBv: ["730000000", "0", "0", "1195000000"],
  //     childrenAggregateBv: ["730000000", "0", "0", "1195000000"],
  //     normalNodesBv: ["230000000", "695000000"],
  //     bv: "0",
  //     eligibleArcWithdrawWeekNo: "6",
  //     superNodeTotalSteps: "1",
  //     bvOnBridgeTime: "0",
  //     fvEntranceMonth: "0",
  //     fvEntranceShare: "0",
  //     minBvForFv: "0",
  //     migrated: true,
  //     withdrawableCommission: "0",
  //     lastArcWithdrawNetworkerWeekNumber: "6",
  //     lastArcWithdrawUserWeekNumber: "0",
  //     createdAt: "1763758499",
  //     active: true
  // },
    {
      parentId: "8",
      userAddress: signers[8].address,
      position: "3",
      path: ["0x0101010101040404000000000000000000000000000000000000000000000000"],
      lastCalculatedOrder: "0",
      childrenBv: ["0", "0", "0", "1195000000"],
      childrenAggregateBv: ["0", "0", "0", "1195000000"],
      normalNodesBv: ["0", "1195000000"],
      bv: "0",
      eligibleArcWithdrawWeekNo: "6",
      superNodeTotalSteps: "0",
      bvOnBridgeTime: "0",
      fvEntranceMonth: "0",
      fvEntranceShare: "0",
      minBvForFv: "0",
      migrated: true,
      withdrawableCommission: "0",
      lastArcWithdrawNetworkerWeekNumber: "0",
      lastArcWithdrawUserWeekNumber: "0",
      createdAt: "1763758499",
      active: true
    },
    {
        parentId: "1",
        userAddress: signers[9].address,
        position: "3",
        path: ["0x0400000000000000000000000000000000000000000000000000000000000000"],
        lastCalculatedOrder: "0",
        childrenBv: ["27852000000", "0", "0", "437588159999"],
        childrenAggregateBv: ["27852000000", "0", "0", "437588159999"],
        normalNodesBv: ["132000000", "218798159999"],
        bv: "0",
        eligibleArcWithdrawWeekNo: "0",
        superNodeTotalSteps: "0",
        bvOnBridgeTime: "0",
        fvEntranceMonth: "0",
        fvEntranceShare: "0",
        minBvForFv: "0",
        migrated: true,
        withdrawableCommission: "0",
        lastArcWithdrawNetworkerWeekNumber: "0",
        lastArcWithdrawUserWeekNumber: "0",
        createdAt: "1763758689",
        active: true
    },
  ];

  /** Whitelist caller, wire oracle/yield/FV, and grant manager role (owner = signers[1]). */
  const setupCoreForTrading = async (
    coreContract: DNMCore,
    addresses: {
      twapAddress: string;
      yieldPoolAddress: string;
      fvAddress: string;
    },
    options?: {
      manager?: HardhatEthersSigner;
      orderCreator?: HardhatEthersSigner;
    },
  ) => {
    const orderCreator = options?.orderCreator ?? signers[1];
    const manager = options?.manager ?? signers[1];
    await coreContract
      .connect(signers[1])
      .addWhiteListContract(orderCreator.address);
    await coreContract.setAddresses(
      addresses.twapAddress,
      addresses.yieldPoolAddress,
      addresses.fvAddress,
    );
    await coreContract.connect(signers[1]).addManager(manager.address);
  };

  const PROTOCOL_OFFSET = 1762732800;

  const getProtocolDayNumber = async () => {
    const block = await ethers.provider.getBlock("latest");
    return Math.floor((block!.timestamp - PROTOCOL_OFFSET) / 86400);
  };

  const getOrderProtocolDay = async (
    coreContract: DNMCore,
    orderId: number,
  ) => {
    const order = await coreContract.getOrderById(orderId);
    return Math.floor((Number(order.createdAt) - PROTOCOL_OFFSET) / 86400);
  };

  const advanceOneProtocolDay = async () => {
    await ethers.provider.send("evm_increaseTime", [86400]);
    await ethers.provider.send("evm_mine", []);
  };

  /** Moves chain time to the first day of the current protocol week (Monday boundary). */
  const moveToFirstDayOfProtocolWeek = async () => {
    const day = await getProtocolDayNumber();
    const weekDay = day % 7;
    if (weekDay !== 0) {
      await ethers.provider.send("evm_increaseTime", [(7 - weekDay) * 86400]);
      await ethers.provider.send("evm_mine", []);
    }
  };

  return {
    deployContracts,
    migrateUserDataMock,
    mockPurchase,
    setupCoreForTrading,
    PROTOCOL_OFFSET,
    getProtocolDayNumber,
    getOrderProtocolDay,
    advanceOneProtocolDay,
    moveToFirstDayOfProtocolWeek,
  };
}
