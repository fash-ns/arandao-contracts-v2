import { BaseContract } from "ethers";
import { getContractData } from "../helpers/contractData.js";
import { core, DNMCore } from "../types/ethers-contracts/index.js";
import { network } from "hardhat";
import { parseError } from "./utils.js";

const main = async (addr: string) => {
    const { ethers } = await network.connect();
    const signers = await ethers.getSigners();
    const contractOwner = signers[0];

    const coreContractData = getContractData("core");

    const coreContract = new BaseContract(
      coreContractData.address,
      coreContractData.abi,
      contractOwner
    ) as DNMCore;

    const userIdByAddr = await coreContract.getUserIdByAddress(addr);

    const userBeforeCalculation = await coreContract.getUserById(userIdByAddr);
    const lastCalculatedOrder = parseInt(userBeforeCalculation.lastCalculatedOrder.toString());

    const orderList = new Array(39 - lastCalculatedOrder).fill(0).map((_, index) => index + lastCalculatedOrder + 1);

    try {
        const calculateOrderTx = await coreContract.calculateOrders(userIdByAddr, orderList);
        console.log(calculateOrderTx.hash);
        await calculateOrderTx.wait();

        const userAfterCalculation = await coreContract.getUserById(userIdByAddr);

    const before = {
        childrenBv: userBeforeCalculation.childrenBv,
        childrenAggregateBv: userBeforeCalculation.childrenAggregateBv,
        normalNodesBv: userBeforeCalculation.normalNodesBv,
        eligibleDnmWithdrawWeekNo: userBeforeCalculation.eligibleDnmWithdrawWeekNo,
        superNodeTotalSteps: userBeforeCalculation.superNodeTotalSteps,
        withdrawableCommission: userBeforeCalculation.withdrawableCommission,
        lastCalculatedOrder: userBeforeCalculation.lastCalculatedOrder,
    }

    const after = {
        childrenBv: userAfterCalculation.childrenBv,
        childrenAggregateBv: userAfterCalculation.childrenAggregateBv,
        normalNodesBv: userAfterCalculation.normalNodesBv,
        eligibleDnmWithdrawWeekNo: userAfterCalculation.eligibleDnmWithdrawWeekNo,
        superNodeTotalSteps: userAfterCalculation.superNodeTotalSteps,
        withdrawableCommission: userAfterCalculation.withdrawableCommission,
        lastCalculatedOrder: userAfterCalculation.lastCalculatedOrder,
    }
    
    const aggrBvDiff = [
        after.childrenAggregateBv[0] - before.childrenAggregateBv[0],
        after.childrenAggregateBv[1] - before.childrenAggregateBv[1],
        after.childrenAggregateBv[2] - before.childrenAggregateBv[2],
        after.childrenAggregateBv[3] - before.childrenAggregateBv[3],
    ]

    console.log({before, after, aggrBvDiff})
    } catch(err: any) {
        console.log(parseError(coreContractData.abi, err.data));
    }
}

const getEligibleArcMonth = async (addrList: string[]) => {
    const { ethers } = await network.connect();
    const signers = await ethers.getSigners();
    const contractOwner = signers[0];

    const coreContractData = getContractData("core");

    const coreContract = new BaseContract(
      coreContractData.address,
      coreContractData.abi,
      contractOwner
    ) as DNMCore;

    for(const addr of addrList) {
        const userId = await coreContract.getUserIdByAddress(addr);
        const user = await coreContract.getUserById(userId);

        console.log({addr, weekNo: user.eligibleDnmWithdrawWeekNo});
    }
}

// getEligibleArcMonth([
//     // '0x76b34b7d6bd27234ad23c434d7f5abc83b32ca4d',
//     // '0x83d27ed16ff6d1221d22b44a93ec33665efbebfc',
//     // '0xF96aD2cA319782Bc71B2150174b64414Ada6dD02',
//     // '0x9f6aef6d10fcbb19b3918e3c76af9dc600ee56cd',
//     // '0x3957dc78f69fa93ce5c3355d68a7310dbf861353',
//     // '0x1edafd24976d6096e1fc6dfa9692150c568c7b72',
//     // '0x02fa2fe5f1cf13d18ccb8b11fb8cf7a55149a508',
//     // '0xf8499823a84162aac6646f63c296e5d1f8088ab5',
//     // '0x5d6620bd762d919f1ddfcaf6ad4044d87f411ad3',
//     // '0xc0429e9ea0eb540071dcdb297bc0be8acf40923a',
//     '0x84d5a106f00486083cc27fc9bfde5779ca898f4b'
// ]);

// main('0x76b34b7d6bd27234ad23c434d7f5abc83b32ca4d');
// main('0x83d27ed16ff6d1221d22b44a93ec33665efbebfc');
// main('0xF96aD2cA319782Bc71B2150174b64414Ada6dD02');
// main('0x9f6aef6d10fcbb19b3918e3c76af9dc600ee56cd');
// main('0x3957dc78f69fa93ce5c3355d68a7310dbf861353');
// main('0x1edafd24976d6096e1fc6dfa9692150c568c7b72');
// main('0x02fa2fe5f1cf13d18ccb8b11fb8cf7a55149a508');
// main('0xf8499823a84162aac6646f63c296e5d1f8088ab5');
// main('0x5d6620bd762d919f1ddfcaf6ad4044d87f411ad3');
// main('0xc0429e9ea0eb540071dcdb297bc0be8acf40923a');
// main('0x84d5a106f00486083cc27fc9bfde5779ca898f4b');

const coreContractData = getContractData("core");
console.log(parseError(coreContractData.abi, "0x8febe2a8000000000000000000000000cda1cf578049c46e7a007a0b00e4f5f2fbe419a5"));