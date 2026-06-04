import { expect } from "chai";
import hre from "hardhat";
import { zeroAddress } from "viem";
import { createCoreTestHelpers } from "../../test-helpers/core-helpers.js";
import { SnapshotRestorer } from "@nomicfoundation/hardhat-network-helpers/types";

const { ethers, networkHelpers } = await hre.network.create();
const signers = await ethers.getSigners();
const {
  deployContracts,
  mockPurchase,
  setupCoreForTrading,
  advanceOneProtocolDay,
} = createCoreTestHelpers(ethers, signers);

const MONTH_18 = 18n;

describe("FastValue supplementary", () => {
  let snapshot: SnapshotRestorer;
  let contracts: Awaited<ReturnType<typeof deployContracts>>;

  before(async () => {
    contracts = await deployContracts();
    snapshot = await networkHelpers.takeSnapshot();
  });

  beforeEach(async () => {
    await snapshot.restore();
  });

  async function wireCoreForFv() {
    const { core, twapAddress, yieldPoolAddress, fvAddress } = contracts;
    await setupCoreForTrading(core, {
      twapAddress,
      yieldPoolAddress,
      fvAddress,
    });
  }

  /** Three-leg tree purchases + one protocol day + calculateOrders → full share FV entrance. */
  async function bootstrapFullShareEntrance(buyer = signers[5]) {
    const { core } = contracts;
    await mockPurchase(core, contracts.usdt, buyer, 101, zeroAddress, 0);
    await mockPurchase(
      core,
      contracts.usdt,
      signers[1],
      1010,
      buyer.address,
      0,
    );
    await mockPurchase(
      core,
      contracts.usdt,
      signers[2],
      1010,
      buyer.address,
      3,
    );
    await advanceOneProtocolDay();
    const userId = await core.getUserIdByAddress(buyer.address);
    await core.connect(signers[1]).calculateOrders(userId, [1, 2, 3]);
    return userId;
  }

  async function fundFv(amount: bigint) {
    const { usdt, fvAddress } = contracts;
    await usdt.connect(signers[1]).transfer(fvAddress, amount);
  }

  async function advanceCalendarMonth() {
    await networkHelpers.time.increase(30 * 86400);
  }

  describe("withdrawFastValueShare", () => {
    it("reverts when withdrawing the current calendar month", async () => {
      const { fv } = contracts;
      await wireCoreForFv();
      const userId = await bootstrapFullShareEntrance();

      expect(await fv.getUserShare(userId, MONTH_18)).to.equal(2);

      await expect(
        fv.connect(signers[5]).withdrawFastValueShare(MONTH_18),
      ).to.be.revertedWithCustomError(fv, "CannotWithdrawCurrentMonthShare");
    });

    it("reverts when the user has no shares", async () => {
      const { fv } = contracts;
      await wireCoreForFv();
      await advanceCalendarMonth();

      await expect(
        fv.connect(signers[6]).withdrawFastValueShare(MONTH_18),
      ).to.be.revertedWithCustomError(fv, "UserNotFound");
    });

    it("reverts when withdrawing the same month twice", async () => {
      const { fv } = contracts;
      await wireCoreForFv();
      await bootstrapFullShareEntrance();
      await advanceCalendarMonth();

      await fv.connect(signers[5]).withdrawFastValueShare(MONTH_18);

      await expect(
        fv.connect(signers[5]).withdrawFastValueShare(MONTH_18),
      ).to.be.revertedWithCustomError(
        fv,
        "UserHasAlreadyWithdrawnFastValueShare",
      );
    });

    it("pays the correct amount for a sole full-share holder", async () => {
      const { fv, usdt } = contracts;
      await wireCoreForFv();
      const userId = await bootstrapFullShareEntrance();

      // mockPurchase BVs 101 + 1010 + 1010 → 20% FV = 424.2 USDT (6 decimals)
      const expectedPayout = 4242n * 10n ** 5n;
      expect(await fv.getUserShareInPaymentToken(userId, MONTH_18)).to.equal(
        expectedPayout,
      );

      await advanceCalendarMonth();

      const balanceBefore = await usdt.balanceOf(signers[5].address);
      await expect(fv.connect(signers[5]).withdrawFastValueShare(MONTH_18))
        .to.emit(fv, "MonthlyFastValueWithdrawn")
        .withArgs(userId, MONTH_18, expectedPayout);

      expect(await usdt.balanceOf(signers[5].address)).to.equal(
        balanceBefore + expectedPayout,
      );
    });

    it("splits monthly FV pro-rata between two users", async () => {
      const { fv, usdt, core } = contracts;
      await wireCoreForFv();

      await mockPurchase(
        core,
        contracts.usdt,
        signers[5],
        1010,
        zeroAddress,
        0,
      );
      await mockPurchase(
        core,
        contracts.usdt,
        signers[6],
        101,
        signers[5].address,
        1,
      );

      const userAId = await core.getUserIdByAddress(signers[5].address);
      const userBId = await core.getUserIdByAddress(signers[6].address);
      const pool = 600n * 10n ** 6n;
      const shareEach = 300n * 10n ** 6n;

      await fv.setTotalMonthlyFv([MONTH_18], [4n], [pool]);
      await fv.setUserMonthlyFv(userAId, [MONTH_18], [2], [false]);
      await fv.setUserMonthlyFv(userBId, [MONTH_18], [2], [false]);
      await fundFv(pool);

      expect(await fv.getUserShareInPaymentToken(userAId, MONTH_18)).to.equal(
        shareEach,
      );
      expect(await fv.getUserShareInPaymentToken(userBId, MONTH_18)).to.equal(
        shareEach,
      );

      await advanceCalendarMonth();

      const balanceA0 = await usdt.balanceOf(signers[5].address);
      const balanceB0 = await usdt.balanceOf(signers[6].address);

      await fv.connect(signers[5]).withdrawFastValueShare(MONTH_18);
      await fv.connect(signers[6]).withdrawFastValueShare(MONTH_18);

      expect(await usdt.balanceOf(signers[5].address)).to.equal(
        balanceA0 + shareEach,
      );
      expect(await usdt.balanceOf(signers[6].address)).to.equal(
        balanceB0 + shareEach,
      );
    });

    it("marks withdrawn and pays zero when monthlyFv is zero", async () => {
      const { fv, usdt, core } = contracts;
      await wireCoreForFv();
      const userId = await bootstrapFullShareEntrance();

      await fv.setTotalMonthlyFv([MONTH_18], [2n], [0n]);
      await advanceCalendarMonth();

      const balanceBefore = await usdt.balanceOf(signers[5].address);

      await expect(fv.connect(signers[5]).withdrawFastValueShare(MONTH_18))
        .to.emit(fv, "MonthlyFastValueWithdrawn")
        .withArgs(userId, MONTH_18, 0n);

      expect(await usdt.balanceOf(signers[5].address)).to.equal(balanceBefore);
      expect(await fv.monthlyUserShareWithdraws(MONTH_18, userId)).to.equal(
        true,
      );
      expect(await fv.getUserShareInPaymentToken(userId, MONTH_18)).to.equal(
        0n,
      );

      await expect(
        fv.connect(signers[5]).withdrawFastValueShare(MONTH_18),
      ).to.be.revertedWithCustomError(
        fv,
        "UserHasAlreadyWithdrawnFastValueShare",
      );
    });

    it("can withdraw multiple closed months in sequence", async () => {
      const { fv, usdt, core } = contracts;
      await wireCoreForFv();
      const userId = await bootstrapFullShareEntrance();
      const month19 = MONTH_18 + 1n;

      await advanceCalendarMonth();
      await mockPurchase(
        core,
        contracts.usdt,
        signers[5],
        1000,
        zeroAddress,
        0,
      );

      expect(await fv.getUserShare(userId, MONTH_18)).to.equal(2);
      expect(await fv.getUserShare(userId, month19)).to.equal(2);

      await advanceCalendarMonth();

      const balance0 = await usdt.balanceOf(signers[5].address);
      const payout18 = await fv.getUserShareInPaymentToken(userId, MONTH_18);
      const payout19 = await fv.getUserShareInPaymentToken(userId, month19);

      await fv.connect(signers[5]).withdrawFastValueShare(MONTH_18);
      await fv.connect(signers[5]).withdrawFastValueShare(month19);

      expect(await usdt.balanceOf(signers[5].address)).to.equal(
        balance0 + payout18 + payout19,
      );
      expect(payout18).to.be.gt(0n);
      expect(payout19).to.be.gt(0n);
    });
  });

  describe("FV entrance (Core integration)", () => {
    it("does not grant FV when superNodeTotalSteps is not greater than one", async () => {
      const { core, fv } = contracts;
      await wireCoreForFv();

      await mockPurchase(core, contracts.usdt, signers[5], 101, zeroAddress, 0);
      await mockPurchase(
        core,
        contracts.usdt,
        signers[1],
        1010,
        signers[5].address,
        0,
      );

      await advanceOneProtocolDay();
      const userId = await core.getUserIdByAddress(signers[5].address);
      await core.connect(signers[1]).calculateOrders(userId, [1, 2]);

      const user = await core.getUserById(userId);
      expect(user.superNodeTotalSteps).to.be.lte(1n);
      expect(user.fvEntranceShare).to.equal(0n);
      expect(await fv.getUserShare(userId, MONTH_18)).to.equal(0);
    });

    it("does not grant FV when the user is older than sixty days", async () => {
      const { core, fv } = contracts;
      await wireCoreForFv();

      await mockPurchase(core, contracts.usdt, signers[5], 101, zeroAddress, 0);
      await networkHelpers.time.increase(61 * 86400);

      await mockPurchase(
        core,
        contracts.usdt,
        signers[1],
        1010,
        signers[5].address,
        0,
      );
      await mockPurchase(
        core,
        contracts.usdt,
        signers[2],
        1010,
        signers[5].address,
        3,
      );

      await advanceOneProtocolDay();
      const userId = await core.getUserIdByAddress(signers[5].address);
      await core.connect(signers[1]).calculateOrders(userId, [2, 3]);

      const user = await core.getUserById(userId);
      expect(user.superNodeTotalSteps).to.be.gt(1n);
      expect(user.fvEntranceShare).to.equal(0n);
      expect(await fv.getUserShare(userId, MONTH_18)).to.equal(0);
    });

    it("emits UserAddedToFastValue on full-share entrance", async () => {
      const { fv } = contracts;
      await wireCoreForFv();

      await mockPurchase(
        contracts.core,
        contracts.usdt,
        signers[5],
        101,
        zeroAddress,
        0,
      );
      await mockPurchase(
        contracts.core,
        contracts.usdt,
        signers[1],
        1010,
        signers[5].address,
        0,
      );
      await mockPurchase(
        contracts.core,
        contracts.usdt,
        signers[2],
        1010,
        signers[5].address,
        3,
      );
      await advanceOneProtocolDay();

      const userId = await contracts.core.getUserIdByAddress(
        signers[5].address,
      );

      await expect(
        contracts.core.connect(signers[1]).calculateOrders(userId, [1, 2, 3]),
      )
        .to.emit(fv, "UserAddedToFastValue")
        .withArgs(userId, MONTH_18, 2);
    });

    it("registerUserFvFromPurchase is a no-op before entrance metadata exists", async () => {
      const { fv, core } = contracts;
      await wireCoreForFv();

      await mockPurchase(core, contracts.usdt, signers[5], 101, zeroAddress, 0);

      expect(await fv.monthlyTotalShares(MONTH_18)).to.equal(0n);
      expect(
        await fv.getUserShare(
          await core.getUserIdByAddress(signers[5].address),
          MONTH_18,
        ),
      ).to.equal(0);
    });

    it("grants half share with correct first-month payout share weight", async () => {
      const { core, fv } = contracts;
      await wireCoreForFv();

      await mockPurchase(core, contracts.usdt, signers[5], 101, zeroAddress, 0);
      await networkHelpers.time.increase(30 * 86400);
      await mockPurchase(
        core,
        contracts.usdt,
        signers[1],
        1010,
        signers[5].address,
        0,
      );
      await mockPurchase(
        core,
        contracts.usdt,
        signers[2],
        1010,
        signers[5].address,
        3,
      );
      await advanceOneProtocolDay();

      const userId = await core.getUserIdByAddress(signers[5].address);
      await core.connect(signers[1]).calculateOrders(userId, [1, 2, 3]);

      await mockPurchase(core, contracts.usdt, signers[5], 100, zeroAddress, 0);
      await advanceOneProtocolDay();
      await core.connect(signers[1]).calculateOrders(userId, [4]);

      await mockPurchase(core, contracts.usdt, signers[5], 20, zeroAddress, 0);
      await advanceOneProtocolDay();
      await core.connect(signers[1]).calculateOrders(userId, [5]);

      const user = await core.getUserById(userId);
      expect(user.fvEntranceShare).to.equal(1n);

      const month19 = MONTH_18 + 1n;
      expect(await fv.getUserShare(userId, month19)).to.equal(1);
      expect(await fv.monthlyTotalShares(month19)).to.equal(1n);

      const pool = await fv.monthlyFv(month19);
      expect(await fv.getUserShareInPaymentToken(userId, month19)).to.equal(
        pool,
      );
    });
  });

  describe("monthly FV funding", () => {
    it("accumulates monthlyFv across multiple purchases in the same month", async () => {
      const { fv } = contracts;
      await wireCoreForFv();

      await mockPurchase(
        contracts.core,
        contracts.usdt,
        signers[5],
        100,
        zeroAddress,
        0,
      );
      expect(await fv.monthlyFv(MONTH_18)).to.equal(20n * 10n ** 6n);

      await mockPurchase(
        contracts.core,
        contracts.usdt,
        signers[5],
        200,
        zeroAddress,
        0,
      );
      expect(await fv.monthlyFv(MONTH_18)).to.equal(60n * 10n ** 6n);
    });
  });

  describe("dev migration helpers", () => {
    it("allows withdraw after manual pool setup and token funding", async () => {
      const { fv, usdt, core } = contracts;
      await wireCoreForFv();

      await mockPurchase(core, contracts.usdt, signers[5], 101, zeroAddress, 0);
      const userId = await core.getUserIdByAddress(signers[5].address);
      const payout = 150n * 10n ** 6n;

      await fv.setTotalMonthlyFv([MONTH_18], [2n], [payout]);
      await fv.setUserMonthlyFv(userId, [MONTH_18], [2], [false]);
      await fundFv(payout);
      await advanceCalendarMonth();

      const balanceBefore = await usdt.balanceOf(signers[5].address);
      await fv.connect(signers[5]).withdrawFastValueShare(MONTH_18);

      expect(await usdt.balanceOf(signers[5].address)).to.equal(
        balanceBefore + payout,
      );
    });

    it("reverts pro-rata view when total shares were not set", async () => {
      const { fv, core } = contracts;
      await wireCoreForFv();

      await mockPurchase(core, contracts.usdt, signers[5], 101, zeroAddress, 0);
      const userId = await core.getUserIdByAddress(signers[5].address);

      await fv.setUserMonthlyFv(userId, [MONTH_18], [2], [false]);

      await expect(
        fv.getUserShareInPaymentToken(userId, MONTH_18),
      ).to.be.revertedWithPanic(0x12);
    });
  });
});
