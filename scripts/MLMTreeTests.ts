import { network } from "hardhat";
import { decodeErrorResult, parseEther } from "viem";
import {
  generatePrivateKey,
  privateKeyToAccount,
  privateKeyToAddress,
} from "viem/accounts";

const { viem } = await network.connect({
  // network: "localhost",
  network: "hardhatMainnet",
  chainType: "l1",
});

const mlmTree = await viem.deployContract("AranDaoProCore", [
  "0xf39fd6e51aad88f6f4ce6ab8827279cfffb92266",
  "0x0000000000000000000000000000000000000002",
  "0x0000000000000000000000000000000000000003",
  "0x0000000000000000000000000000000000000004"
]);

// const mlmTree = await viem.getContractAt("AranDaoProCore", "0x5FC8d32690cc91D4c39d9d3abcBD16989F875707");

  await mlmTree.write.migrateUser([
    `0x70997970c51812dc3a010c7d01b50e0d17dc79c8`,
    0n,
    0,
    0n,
    0n,
    [0n, 0n, 0n, 0n],
    [0n, 0n, 0n, 0n]
  ]);

  const id = await mlmTree.read.getUserIdByAddress(['0x70997970c51812dc3a010c7d01b50e0d17dc79c8']);
  console.log({id});
  for (let i = 1; i <= 33; i++) {
    const pk = generatePrivateKey();
    const address = privateKeyToAddress(pk);
    const pos = Math.floor(Math.random() * 4);
    await mlmTree.write.migrateUser([
      address,
      BigInt(i),
      pos,
      BigInt(i) * parseEther('132'),
      parseEther('40'),
      [0n, 0n, 0n, 0n],
      [0n, 0n, 0n, 0n]
    ]);
    const id = await mlmTree.read.getUserIdByAddress([address]);
    console.log(`${address}: ${id}`);
  }
  const res = await mlmTree.read.getUserById([34n]);
  console.log(res);