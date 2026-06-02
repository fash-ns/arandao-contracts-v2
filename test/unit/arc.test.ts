import { expect } from "chai";
import hre from "hardhat";
import { createCoreTestHelpers } from "../../test-helpers/core-helpers.js";
import { SnapshotRestorer } from "@nomicfoundation/hardhat-network-helpers/types";
import { zeroAddress } from "viem";

const { ethers, networkHelpers } = await hre.network.create();
const signers = await ethers.getSigners();
const { deployContracts, migrateUserDataMock, mockPurchase } =
  createCoreTestHelpers(ethers, signers);

describe("AssetRightsCoin", () => {
  let snapshot: SnapshotRestorer;
  let contracts: Awaited<ReturnType<typeof deployContracts>>;

  before(async () => {
    contracts = await deployContracts();
    snapshot = await networkHelpers.takeSnapshot();
  });

  beforeEach(async () => {
    await snapshot.restore();
  });

  it("Only deployer can set mint operator", async () => {
    const { arc } = contracts;

    await expect(
      arc
        .connect(signers[2])
        .setMintOperator("0x0000000000000000000000000000000000000001"),
    ).to.be.revertedWith("Only deployer can call");

    await arc
      .connect(signers[0])
      .setMintOperator("0x0000000000000000000000000000000000000001");
    expect(await arc.mintOperator()).to.equal(
      "0x0000000000000000000000000000000000000001",
    );
  });

  it("Mint operator cannot be set twice", async () => {
    const { arc } = contracts;

    await arc.setMintOperator("0x0000000000000000000000000000000000000001");

    await expect(
      arc.setMintOperator("0x0000000000000000000000000000000000000001"),
    ).to.be.revertedWith("Mint operator is allready set.");
  });

  it("Deployer should call for revoke deployer", async () => {
    const { arc } = contracts;

    await arc.revokeDeployer();

    expect(await arc.deployer()).to.equal(zeroAddress);
  });

  it("Even deployer cannot set mint operator after revoke", async () => {
    const { arc } = contracts;

    await arc.revokeDeployer();

    await expect(
      arc
        .connect(signers[0])
        .setMintOperator("0x0000000000000000000000000000000000000001"),
    ).to.be.revertedWith("Only deployer can call");
  });
});
