import { network } from "hardhat";
import { getContractData } from "../helpers/contractData.js";
import { DNMCore } from "../types/ethers-contracts/index.js";
import { Result } from "ethers";
import * as fs from "fs";
import * as path from "path";
import readline from "readline";

const { ethers } = await network.connect();
const signers = await ethers.getSigners();
const contractOwner = signers[0];

const rl = readline.createInterface({
  input: process.stdin,
  output: process.stdout,
});

const coreContractData = getContractData("core");

const getUserById = async (id: bigint, log?: boolean) => {
  const coreContractData = getContractData("core");

  const coreContract = new ethers.BaseContract(
    coreContractData.address,
    coreContractData.abi,
    contractOwner,
  ) as DNMCore;

  const user = await coreContract.getUserById(id);

  if (log) {
    console.log((user as any).toObject(true));
  }

  return user;
};

const getTxData = async () => {
  const tx = await ethers.provider.getTransaction(
    "0x5b2032d7d4a2f995d4fc598932ecdfb1550df08e8e81409d43051ac2db60f3da",
  );
  const iface = new ethers.Interface(coreContractData.abi);

  const txData = iface.parseTransaction({ data: tx!.data });
  console.log(txData);
};

const getTxNonce = async () => {
  const tx = await ethers.provider.getTransaction(
    "0x26c2d96976976bc602b3f9328abb89bc8ba02f40a712f4c6f00f9ca0816ac8a2",
  );

  console.log(tx?.nonce);
};

const pressAKey = async () => {
  return new Promise<void>((resolve) => {
    rl.question("Press enter to continue", (name) => {
      resolve();
    });
  });
};

// childrenBv: [ 171746000000000000000000n, 0n, 0n, 0n ],
//   childrenAggregateBv: [ 171746000000000000000000n, 0n, 0n, 0n ],
//   normalNodesBv: [ 171746000000000000000000n, 0n ],

const main = async () => {
  const fileData = JSON.parse(
    fs.readFileSync(path.resolve("./personal", "addonBvs.json")).toString(),
  );

  const fileDataLen = fileData.length;

  for (let i = 1; i < fileDataLen; i++) {
    console.log(`Updating for index ${i}`);
    const item = fileData[i];

    const user: Result = (await getUserById(item.userId)) as any;
    console.log(`user Before`, user.toObject(true));
    const userArr = user.toArray(true);

    userArr[5][0] += BigInt(item.bvs[0]);
    userArr[5][1] += BigInt(item.bvs[1]);
    userArr[5][2] += BigInt(item.bvs[2]);
    userArr[5][3] += BigInt(item.bvs[3]);

    userArr[6][0] += BigInt(item.bvs[0]);
    userArr[6][1] += BigInt(item.bvs[1]);
    userArr[6][2] += BigInt(item.bvs[2]);
    userArr[6][3] += BigInt(item.bvs[3]);

    userArr[7][0] += BigInt(item.bvs[0]) + BigInt(item.bvs[1]);
    userArr[7][1] += BigInt(item.bvs[2]) + BigInt(item.bvs[3]);

    const coreContractData = getContractData("core");

    const coreContract = new ethers.BaseContract(
      coreContractData.address,
      coreContractData.abi,
      contractOwner,
    ) as DNMCore;

    const inputData = {
      parentId: userArr[0],
      userAddress: userArr[1],
      position: userArr[2],
      path: userArr[3],
      lastCalculatedOrder: userArr[4],
      childrenBv: userArr[5],
      childrenAggregateBv: userArr[6],
      normalNodesBv: userArr[7],
      bv: userArr[8],
      eligibleDnmWithdrawWeekNo: userArr[9],
      superNodeTotalSteps: userArr[10],
      bvOnBridgeTime: userArr[11],
      fvEntranceMonth: userArr[12],
      fvEntranceShare: userArr[13],
      networkerDnmShare: userArr[14],
      withdrawNetworkerDnmShareMonth: userArr[15],
      migrated: userArr[16],
      withdrawableCommission: userArr[17],
      lastDnmWithdrawNetworkerWeekNumber: userArr[18],
      lastDnmWithdrawUserWeekNumber: userArr[19],
      createdAt: userArr[20],
      active: userArr[21],
    };

    const tx = await coreContract.updateUserById(
      BigInt(item.userId),
      inputData,
      {
        gasPrice: ethers.parseUnits("95", "gwei"),
      },
    );
    console.log(`txHash: ${tx.hash}`);
    await tx.wait();

    const userAfter: Result = (await getUserById(item.userId)) as any;

    console.log(`user After`, userAfter.toObject(true));

    console.log(`----------------`);

    await pressAKey();
  }

  // await tx.wait();

  // await getUserById(1n);
};

const addCommission = async (userId: bigint, amount: bigint) => {
  const user: Result = (await getUserById(userId)) as any;
  console.log(`user Before`, user.toObject(true));
  const userArr = user.toArray(true);

  const coreContractData = getContractData("core");

  userArr[17] = userArr[17] + amount;

  const coreContract = new ethers.BaseContract(
    coreContractData.address,
    coreContractData.abi,
    contractOwner,
  ) as DNMCore;

  const inputData = {
    parentId: userArr[0],
    userAddress: userArr[1],
    position: userArr[2],
    path: userArr[3],
    lastCalculatedOrder: userArr[4],
    childrenBv: userArr[5],
    childrenAggregateBv: userArr[6],
    normalNodesBv: userArr[7],
    bv: userArr[8],
    eligibleDnmWithdrawWeekNo: userArr[9],
    superNodeTotalSteps: userArr[10],
    bvOnBridgeTime: userArr[11],
    fvEntranceMonth: userArr[12],
    fvEntranceShare: userArr[13],
    networkerDnmShare: userArr[14],
    withdrawNetworkerDnmShareMonth: userArr[15],
    migrated: userArr[16],
    withdrawableCommission: userArr[17],
    lastDnmWithdrawNetworkerWeekNumber: userArr[18],
    lastDnmWithdrawUserWeekNumber: userArr[19],
    createdAt: userArr[20],
    active: userArr[21],
  };

  const tx = await coreContract.updateUserById(userId, inputData);
  console.log(`txHash: ${tx.hash}`);
  await tx.wait();

  const userAfter: Result = (await getUserById(userId)) as any;
};

// await tx.wait();

// await getUserById(1n);

await addCommission(652n, BigInt("60000000000000000000"));
// getTxData();
// getTxNonce();
