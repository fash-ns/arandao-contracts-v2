import { expect } from "chai";
import hre from "hardhat";
import { createCoreTestHelpers } from "../../test-helpers/core-helpers.js";
import { SnapshotRestorer } from "@nomicfoundation/hardhat-network-helpers/types";

const { ethers, networkHelpers } = await hre.network.create();
const signers = await ethers.getSigners();
const { deployContracts, migrateUserDataMock, mockPurchase } =
  createCoreTestHelpers(ethers, signers);

describe("FastValue", () => {
  let snapshot: SnapshotRestorer;
  let contracts: Awaited<ReturnType<typeof deployContracts>>;

  before(async () => {
    contracts = await deployContracts();
    snapshot = await networkHelpers.takeSnapshot();
  });

  beforeEach(async () => {
    await snapshot.restore();
  });

  it("No one but core can't check user authority for FV entrance", async () => {
    const { fv } = contracts;

    await expect(
      fv.checkUserAuthorityForFvEntrance(
        migrateUserDataMock[0],
        1,
        100000000,
        18,
        Math.floor(new Date().getTime() / 1000),
      ),
    ).to.be.revertedWithCustomError(fv, "UnAuthorizedCoreContract");
  });

  it("No one but core can't register user FV from purchase", async () => {
    const { fv } = contracts;

    await expect(
      fv.registerUserFvFromPurchase(migrateUserDataMock[0], 1, 18),
    ).to.be.revertedWithCustomError(fv, "UnAuthorizedCoreContract");
  });

  it("No one but core can't add monthly FV", async () => {
    const { fv } = contracts;

    await expect(fv.addMonthlyFv(18, 100 * 1e6)).to.be.revertedWithCustomError(
      fv,
      "UnAuthorizedCoreContract",
    );
  });

  it("No one but owner can't set total monthly FV", async () => {
    const { fv } = contracts;

    await expect(
      fv.connect(signers[1]).setTotalMonthlyFv(18, 10, 100 * 1e6),
    ).to.be.revertedWithCustomError(fv, "UnAuthorizedOwner");

    await fv.setTotalMonthlyFv(18, 10, 100 * 1e6);

    expect(await fv.monthlyTotalShares(18)).to.equals(10);
    expect(await fv.monthlyFv(18)).to.equals(100 * 1e6);
  });

  it("No one but owner can't set user monthly FV", async () => {
    const { fv } = contracts;

    await expect(
      fv.connect(signers[1]).setUserMonthlyFv(18, 1, 2, false),
    ).to.be.revertedWithCustomError(fv, "UnAuthorizedOwner");

    await fv.setUserMonthlyFv(18, 1, 2, true);

    await fv.setUserMonthlyFv(19, 1, 2, false);

    expect(await fv.monthlyUserShareWithdraws(18, 1)).to.equals(true);
    expect(await fv.monthlyUserShares(18, 1)).to.equals(2);
    expect(await fv.monthlyUserShareWithdraws(19, 1)).to.equals(false);
    expect(await fv.monthlyUserShares(19, 1)).to.equals(2);
  });

  it("only owner can revoke devMode", async () => {
    const { fv } = contracts;

    await expect(
      fv.connect(signers[1]).revokeDevMode(),
    ).to.be.revertedWithCustomError(fv, "UnAuthorizedOwner");

    await fv.revokeDevMode();

    expect(await fv.devMode()).to.be.false;
  });

  it("Even owner can't set user montly FV after devMode", async () => {
    const { fv } = contracts;

    await fv.revokeDevMode();

    await expect(
      fv.connect(signers[1]).setUserMonthlyFv(18, 1, 2, false),
    ).to.be.revertedWithCustomError(fv, "NotInDevMode");
  });

  it("Even owner can't set total montly FV after devMode", async () => {
    const { fv } = contracts;

    await fv.revokeDevMode();

    await expect(
      fv.connect(signers[1]).setTotalMonthlyFv(18, 10, 100 * 1e6),
    ).to.be.revertedWithCustomError(fv, "NotInDevMode");
  });
});
