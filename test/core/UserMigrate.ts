import { describe, it } from "node:test";
import assert from "node:assert/strict";

import { network } from "hardhat";
import { walletActions } from "viem";

describe("Core.User", async function () {
  const { viem } = await network.connect();
  const publicClient = (await viem.getPublicClient()).extend(walletActions);

  const addresses = await publicClient.getAddresses();

  it("Should migrate first user", async function () {
    const coreContract = await viem.deployContract("AranDaoProCore", [
      addresses[0],
      "0x0000000000000000000000000000000000000002",
      "0x0000000000000000000000000000000000000003",
      "0x0000000000000000000000000000000000000004"    
    ]);

    await viem.assertions.emitWithArgs(
        coreContract.write.migrateUser([[{
          userAddr: `0x70997970C51812dc3A010C7d01b50e0d17dc79C8`,
           parentAddr: `0x0000000000000000000000000000000000000000`,
           position: 0,
           bv: 0n,
           childrenSafeBv: [0n, 0n, 0n, 0n],
           childrenAggregateBv: [0n, 0n, 0n, 0n]
       }]]),
          coreContract,
          "UserMigrated",
          [1n, 0n, 0, '0x70997970C51812dc3A010C7d01b50e0d17dc79C8']
    )
  });

  it("Shouldn't migrate first user when parent is not root", async function () {
    const coreContract = await viem.deployContract("AranDaoProCore", [
      addresses[0],
      "0x0000000000000000000000000000000000000002",
      "0x0000000000000000000000000000000000000003",
      "0x0000000000000000000000000000000000000004"    
    ]);

    await viem.assertions.revertWithCustomError(
        coreContract.write.migrateUser([[{
          userAddr: `0x70997970C51812dc3A010C7d01b50e0d17dc79C8`,
           parentAddr: `0x0000000000000000000000000000000000000020`,
           position: 0,
           bv: 0n,
           childrenSafeBv: [0n, 0n, 0n, 0n],
           childrenAggregateBv: [0n, 0n, 0n, 0n]
       }]]),
          coreContract,
          "FirstUserMustBeRoot"
    )
  });

  it("Shouldn't migrate first user when position is not zero", async function () {
    const coreContract = await viem.deployContract("AranDaoProCore", [
      addresses[0],
      "0x0000000000000000000000000000000000000002",
      "0x0000000000000000000000000000000000000003",
      "0x0000000000000000000000000000000000000004"    
    ]);

    await viem.assertions.revertWithCustomError(
        coreContract.write.migrateUser([
            `0x70997970c51812dc3a010c7d01b50e0d17dc79c8`,
            0n,
            1,
            0n,
            0n,
            [0n, 0n, 0n, 0n],
            [0n, 0n, 0n, 0n]
          ]),
          coreContract,
          "FirstUserMustBeRoot"
    )
  });

  it("Shouldn't migrate second user with the same address", async function () {
    const coreContract = await viem.deployContract("AranDaoProCore", [
      addresses[0],
      "0x0000000000000000000000000000000000000002",
      "0x0000000000000000000000000000000000000003",
      "0x0000000000000000000000000000000000000004"    
    ]);

    await viem.assertions.emitWithArgs(
        coreContract.write.migrateUser([
            `0x70997970C51812dc3A010C7d01b50e0d17dc79C8`,
            0n,
            0,
            0n,
            0n,
            [0n, 0n, 0n, 0n],
            [0n, 0n, 0n, 0n]
          ]),
          coreContract,
          "UserMigrated",
          [1n, 0n, 0, '0x70997970C51812dc3A010C7d01b50e0d17dc79C8']
    )

    await viem.assertions.revertWithCustomError(
        coreContract.write.migrateUser([
            `0x70997970c51812dc3a010c7d01b50e0d17dc79c8`,
            0n,
            1,
            0n,
            0n,
            [0n, 0n, 0n, 0n],
            [0n, 0n, 0n, 0n]
          ]),
          coreContract,
          "UserAlreadyRegistered"
    )
  });

  it("Shouldn't migrate second user with the not existed parent", async function () {
    const coreContract = await viem.deployContract("AranDaoProCore", [
      addresses[0],
      "0x0000000000000000000000000000000000000002",
      "0x0000000000000000000000000000000000000003",
      "0x0000000000000000000000000000000000000004"    
    ]);

    await viem.assertions.emitWithArgs(
        coreContract.write.migrateUser([
            `0x70997970C51812dc3A010C7d01b50e0d17dc79C8`,
            0n,
            0,
            0n,
            0n,
            [0n, 0n, 0n, 0n],
            [0n, 0n, 0n, 0n]
          ]),
          coreContract,
          "UserMigrated",
          [1n, 0n, 0, '0x70997970C51812dc3A010C7d01b50e0d17dc79C8']
    )

    await viem.assertions.revertWithCustomError(
        coreContract.write.migrateUser([
            `0x70997970c51812dc3a010c7d01b50e0d17dc79c1`,
            0n,
            2,
            0n,
            0n,
            [0n, 0n, 0n, 0n],
            [0n, 0n, 0n, 0n]
          ]),
          coreContract,
          "InvalidParentId"
    )
  });

  it("Shouldn't migrate second user with the zero as parent", async function () {
    const coreContract = await viem.deployContract("AranDaoProCore", [
      addresses[0],
      "0x0000000000000000000000000000000000000002",
      "0x0000000000000000000000000000000000000003",
      "0x0000000000000000000000000000000000000004"    
    ]);

    await viem.assertions.emitWithArgs(
        coreContract.write.migrateUser([
            `0x70997970C51812dc3A010C7d01b50e0d17dc79C8`,
            0n,
            0,
            0n,
            0n,
            [0n, 0n, 0n, 0n],
            [0n, 0n, 0n, 0n]
          ]),
          coreContract,
          "UserMigrated",
          [1n, 0n, 0, '0x70997970C51812dc3A010C7d01b50e0d17dc79C8']
    )

    await viem.assertions.revertWithCustomError(
        coreContract.write.migrateUser([
            `0x70997970c51812dc3a010c7d01b50e0d17dc79c1`,
            0n,
            0,
            0n,
            0n,
            [0n, 0n, 0n, 0n],
            [0n, 0n, 0n, 0n]
          ]),
          coreContract,
          "InvalidParentId"
    )
  });

  it("Should migrate second user", async function () {
    const coreContract = await viem.deployContract("AranDaoProCore", [
      addresses[0],
      "0x0000000000000000000000000000000000000002",
      "0x0000000000000000000000000000000000000003",
      "0x0000000000000000000000000000000000000004"    
    ]);

    await viem.assertions.emitWithArgs(
        coreContract.write.migrateUser([
            `0x70997970C51812dc3A010C7d01b50e0d17dc79C8`,
            0n,
            0,
            0n,
            0n,
            [0n, 0n, 0n, 0n],
            [0n, 0n, 0n, 0n]
          ]),
          coreContract,
          "UserMigrated",
          [1n, 0n, 0, '0x70997970C51812dc3A010C7d01b50e0d17dc79C8']
    )

    await viem.assertions.emitWithArgs(
        coreContract.write.migrateUser([
            `0x70997970c51812dc3a010c7d01b50e0d17dc79c1`,
            1n,
            0,
            0n,
            0n,
            [0n, 0n, 0n, 0n],
            [0n, 0n, 0n, 0n]
          ]),
          coreContract,
          "UserMigrated",
          [2n, 1n, 0, '0x70997970C51812DC3A010c7D01b50E0D17DC79C1']
    )
  });

  it("Shouldn't migrate third user for reserved position", async function () {
    const coreContract = await viem.deployContract("AranDaoProCore", [
      addresses[0],
      "0x0000000000000000000000000000000000000002",
      "0x0000000000000000000000000000000000000003",
      "0x0000000000000000000000000000000000000004"    
    ]);

    await viem.assertions.emitWithArgs(
        coreContract.write.migrateUser([
            `0x70997970C51812dc3A010C7d01b50e0d17dc79C8`,
            0n,
            0,
            0n,
            0n,
            [0n, 0n, 0n, 0n],
            [0n, 0n, 0n, 0n]
          ]),
          coreContract,
          "UserMigrated",
          [1n, 0n, 0, '0x70997970C51812dc3A010C7d01b50e0d17dc79C8']
    )

    await viem.assertions.emitWithArgs(
        coreContract.write.migrateUser([
            `0x70997970c51812dc3a010c7d01b50e0d17dc79c1`,
            1n,
            0,
            0n,
            0n,
            [0n, 0n, 0n, 0n],
            [0n, 0n, 0n, 0n]
          ]),
          coreContract,
          "UserMigrated",
          [2n, 1n, 0, '0x70997970C51812DC3A010c7D01b50E0D17DC79C1']
    )
    await viem.assertions.revertWithCustomError(
        coreContract.write.migrateUser([
            `0x70997970c51812dc3a010c7d01b50e0d17dc79c2`,
            1n,
            0,
            0n,
            0n,
            [0n, 0n, 0n, 0n],
            [0n, 0n, 0n, 0n]
          ]),
          coreContract,
          "PositionAlreadyTaken"
    )
  });

  it("Should migrate third user with correct path", async function () {
    const coreContract = await viem.deployContract("AranDaoProCore", [
      addresses[0],
      "0x0000000000000000000000000000000000000002",
      "0x0000000000000000000000000000000000000003",
      "0x0000000000000000000000000000000000000004"    
    ]);

    await viem.assertions.emitWithArgs(
        coreContract.write.migrateUser([
            `0x70997970C51812dc3A010C7d01b50e0d17dc79C8`,
            0n,
            0,
            0n,
            0n,
            [0n, 0n, 0n, 0n],
            [0n, 0n, 0n, 0n]
          ]),
          coreContract,
          "UserMigrated",
          [1n, 0n, 0, '0x70997970C51812dc3A010C7d01b50e0d17dc79C8']
    )

    await viem.assertions.emitWithArgs(
        coreContract.write.migrateUser([
            `0x70997970c51812dc3a010c7d01b50e0d17dc79c1`,
            1n,
            1,
            0n,
            0n,
            [0n, 0n, 0n, 0n],
            [0n, 0n, 0n, 0n]
          ]),
          coreContract,
          "UserMigrated",
          [2n, 1n, 1, '0x70997970C51812DC3A010c7D01b50E0D17DC79C1']
    )
    await viem.assertions.emitWithArgs(
      coreContract.write.migrateUser([
        `0x70997970c51812dc3a010c7d01b50e0d17dc79c2`,
        2n,
        2,
        0n,
        0n,
        [0n, 0n, 0n, 0n],
        [0n, 0n, 0n, 0n]
      ]),
      coreContract,
      "UserMigrated",
      [3n, 2n, 2, '0x70997970c51812DC3a010c7d01B50E0D17dC79C2']
    )
  const thirdUser = await coreContract.read.getUserById([3n]);
  assert.deepEqual(thirdUser.path, ['0x0203000000000000000000000000000000000000000000000000000000000000']);
  });
})