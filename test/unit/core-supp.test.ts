import { expect } from "chai";
import { parseEther } from "ethers";
import hre from "hardhat";
import { zeroAddress } from "viem";
import { createCoreTestHelpers } from "../../test-helpers/core-helpers.js";
import { SnapshotRestorer } from "@nomicfoundation/hardhat-network-helpers/types";

const { ethers, networkHelpers } = await hre.network.create();
const signers = await ethers.getSigners();
const {
  deployContracts,
  migrateUserDataMock,
  mockPurchase,
  setupCoreForTrading,
  getOrderProtocolDay,
  advanceOneProtocolDay,
  moveToFirstDayOfProtocolWeek,
} = createCoreTestHelpers(ethers, signers);

describe("DNMCore supplementary", function () {
  let snapshot: SnapshotRestorer;
  let contracts: Awaited<ReturnType<typeof deployContracts>>;

  before(async function () {
    contracts = await deployContracts();
    snapshot = await networkHelpers.takeSnapshot();
  });

  beforeEach(async function () {
    await snapshot.restore();
  });

  describe("createOrder", function () {
    it("reverts when caller is not a whitelisted order creator", async function () {
      const { core, twapAddress, yieldPoolAddress, fvAddress } = contracts;
      await setupCoreForTrading(core, {
        twapAddress,
        yieldPoolAddress,
        fvAddress,
      });

      await expect(
        core.connect(signers[2]).createOrder(
          signers[2].address,
          zeroAddress,
          0,
          [{ sellerAddress: signers[9].address, bv: 100n * 10n ** 6n, sv: 0 }],
          100n * 10n ** 6n,
        ),
      ).to.be.revertedWithCustomError(core, "UnauthorizedContract");
    });

    it("reverts when amounts array is empty", async function () {
      const { core, twapAddress, yieldPoolAddress, fvAddress } = contracts;
      await setupCoreForTrading(core, {
        twapAddress,
        yieldPoolAddress,
        fvAddress,
      });

      await expect(
        core.connect(signers[1]).createOrder(
          signers[1].address,
          zeroAddress,
          0,
          [],
          0,
        ),
      ).to.be.revertedWith("At least one amount required");
    });

    it("reverts when new user BV is below minimum", async function () {
      const { core, usdt, coreAddress, twapAddress, yieldPoolAddress, fvAddress } =
        contracts;
      await setupCoreForTrading(core, {
        twapAddress,
        yieldPoolAddress,
        fvAddress,
      });

      const newBuyer = signers[8];
      await usdt
        .connect(signers[1])
        .approve(coreAddress, 51n * 10n ** 6n);

      await expect(
        core.connect(signers[1]).createOrder(
          newBuyer.address,
          zeroAddress,
          0,
          [
            {
              sellerAddress: signers[9].address,
              bv: 50n * 10n ** 6n,
              sv: 0,
            },
          ],
          51n * 10n ** 6n,
        ),
      ).to.be.revertedWithCustomError(core, "InsufficientBVForNewUser");
    });

    it("reverts when position is already taken under parent", async function () {
      const { core, usdt, twapAddress, yieldPoolAddress, fvAddress } = contracts;
      await setupCoreForTrading(core, {
        twapAddress,
        yieldPoolAddress,
        fvAddress,
      });

      await mockPurchase(core, usdt, signers[0], 100, zeroAddress, 0);
      await mockPurchase(core, usdt, signers[5], 100, signers[0].address, 0);
      await mockPurchase(core, usdt, signers[1], 100, signers[5].address, 0);

      await expect(
        mockPurchase(core, usdt, signers[2], 100, signers[5].address, 0),
      ).to.be.revertedWithCustomError(core, "PositionAlreadyTaken");
    });

    it("reverts when position is greater than 3", async function () {
      const { core, usdt, coreAddress, twapAddress, yieldPoolAddress, fvAddress } =
        contracts;
      await setupCoreForTrading(core, {
        twapAddress,
        yieldPoolAddress,
        fvAddress,
      });

      await mockPurchase(core, usdt, signers[0], 100, zeroAddress, 0);
      await usdt.connect(signers[1]).approve(coreAddress, 101n * 10n ** 6n);

      await expect(
        core.connect(signers[1]).createOrder(
          signers[4].address,
          signers[0].address,
          4,
          [
            {
              sellerAddress: signers[9].address,
              bv: 100n * 10n ** 6n,
              sv: 0,
            },
          ],
          101n * 10n ** 6n,
        ),
      ).to.be.revertedWithCustomError(core, "InvalidPosition");
    });

    it("reverts when non-owner adds whitelist entry", async function () {
      const { core } = contracts;
      await expect(
        core.connect(signers[2]).addWhiteListContract(signers[2].address),
      ).to.be.revertedWithCustomError(core, "UnauthorizedAddress");
    });
  });

  describe("calculateOrders", function () {
    async function buildPairZeroTree() {
      const { core, usdt } = contracts;
      await mockPurchase(core, usdt, signers[0], 100, zeroAddress, 0);
      await mockPurchase(core, usdt, signers[5], 100, signers[0].address, 0);
      // Parent needs >= 200 BV before accepting position 1 under them.
      await mockPurchase(core, usdt, signers[5], 100, zeroAddress, 0);
      await mockPurchase(core, usdt, signers[1], 1000, signers[5].address, 0);
      await mockPurchase(core, usdt, signers[2], 1000, signers[5].address, 1);
      return await core.getUserIdByAddress(signers[5].address);
    }

    async function buildDeepLineTree() {
      const { core, usdt } = contracts;
      await mockPurchase(core, usdt, signers[0], 100, zeroAddress, 0);
      await mockPurchase(core, usdt, signers[5], 100, signers[0].address, 0);
      await mockPurchase(core, usdt, signers[5], 100, zeroAddress, 0);
      return await core.getUserIdByAddress(signers[5].address);
    }

    async function buildThreeLegTree() {
      const { core, usdt } = contracts;
      await mockPurchase(core, usdt, signers[0], 100, zeroAddress, 0);
      await mockPurchase(core, usdt, signers[5], 100, signers[0].address, 0);
      await mockPurchase(core, usdt, signers[5], 100, zeroAddress, 0);
      await mockPurchase(core, usdt, signers[5], 100, zeroAddress, 0);
      await mockPurchase(core, usdt, signers[1], 1000, signers[5].address, 0);
      await mockPurchase(core, usdt, signers[2], 1000, signers[5].address, 1);
      await mockPurchase(core, usdt, signers[3], 1000, signers[5].address, 2);
      return await core.getUserIdByAddress(signers[5].address);
    }

    it("reverts when caller is not a manager", async function () {
      const { core, twapAddress, yieldPoolAddress, fvAddress } = contracts;
      await setupCoreForTrading(core, {
        twapAddress,
        yieldPoolAddress,
        fvAddress,
      });
      const uplineId = await buildPairZeroTree();
      await advanceOneProtocolDay();

      await expect(
        core.connect(signers[2]).calculateOrders(uplineId, [4, 5]),
      ).to.be.revertedWithCustomError(core, "UnauthorizedAddress");
    });

    it("reverts when processing orders from the current protocol day", async function () {
      const { core, twapAddress, yieldPoolAddress, fvAddress } = contracts;
      await setupCoreForTrading(core, {
        twapAddress,
        yieldPoolAddress,
        fvAddress,
      });
      const uplineId = await buildPairZeroTree();

      await expect(
        core.connect(signers[1]).calculateOrders(uplineId, [4, 5]),
      ).to.be.revertedWith("Cannot process orders from current day.");
    });

    it("reverts when an order was already processed", async function () {
      const { core, twapAddress, yieldPoolAddress, fvAddress } = contracts;
      await setupCoreForTrading(core, {
        twapAddress,
        yieldPoolAddress,
        fvAddress,
      });
      const uplineId = await buildPairZeroTree();
      await advanceOneProtocolDay();

      await core.connect(signers[1]).calculateOrders(uplineId, [4, 5]);

      await expect(
        core.connect(signers[1]).calculateOrders(uplineId, [4]),
      ).to.be.revertedWith(
        "Order with greater ID is already processed for this user.",
      );
    });

    it("credits pair 0 (childrenBv[0] vs [1]) with two daily steps", async function () {
      const { core, twapAddress, yieldPoolAddress, fvAddress } = contracts;
      await setupCoreForTrading(core, {
        twapAddress,
        yieldPoolAddress,
        fvAddress,
      });
      const uplineId = await buildPairZeroTree();
      await advanceOneProtocolDay();

      await core.connect(signers[1]).calculateOrders(uplineId, [4, 5]);

      const user = await core.getUserById(uplineId);
      const orderDay = await getOrderProtocolDay(core, 5);

      expect(user.withdrawableCommission).to.equal(120n * 10n ** 6n);
      expect(await core.userDailySteps(uplineId, orderDay, 0)).to.equal(2);
      expect(await core.userDailySteps(uplineId, orderDay, 1)).to.equal(0);
      expect(await core.userDailySteps(uplineId, orderDay, 2)).to.equal(0);
      expect(user.childrenBv[0]).to.equal(0);
      expect(user.childrenBv[3]).to.equal(0);
    });

    it("flushes pair 0 after six steps and increments global flush counter", async function () {
      const { core, usdt, twapAddress, yieldPoolAddress, fvAddress } = contracts;
      await setupCoreForTrading(core, {
        twapAddress,
        yieldPoolAddress,
        fvAddress,
      });

      await mockPurchase(core, usdt, signers[0], 100, zeroAddress, 0);
      await mockPurchase(core, usdt, signers[5], 100, signers[0].address, 0);
      await mockPurchase(core, usdt, signers[5], 100, zeroAddress, 0);
      await mockPurchase(core, usdt, signers[1], 5000, signers[5].address, 0);
      await mockPurchase(core, usdt, signers[2], 5000, signers[5].address, 3);

      const uplineId = await core.getUserIdByAddress(signers[5].address);
      await advanceOneProtocolDay();
      const orderDay = await getOrderProtocolDay(core, 5);

      await core.connect(signers[1]).calculateOrders(uplineId, [4, 5]);

      const user = await core.getUserById(uplineId);
      expect(user.withdrawableCommission).to.equal(360n * 10n ** 6n);
      expect(await core.userDailySteps(uplineId, orderDay, 2)).to.equal(6);
      expect(user.normalNodesBv[0]).to.equal(0);
      expect(user.normalNodesBv[1]).to.equal(0);
      expect(await core.globalDailyFlushOuts(orderDay)).to.equal(1n);
      expect(await core.weeklyCalculationStartTime()).to.equal(0);
    });

    it("does not credit BV when buyer is the upline (same node)", async function () {
      const { core, usdt, twapAddress, yieldPoolAddress, fvAddress } = contracts;
      await setupCoreForTrading(core, {
        twapAddress,
        yieldPoolAddress,
        fvAddress,
      });

      await mockPurchase(core, usdt, signers[0], 100, zeroAddress, 0);
      await mockPurchase(core, usdt, signers[5], 100, signers[0].address, 0);

      const uplineId = await core.getUserIdByAddress(signers[5].address);
      await advanceOneProtocolDay();

      await core.connect(signers[1]).calculateOrders(uplineId, [2]);

      const user = await core.getUserById(uplineId);
      expect(user.withdrawableCommission).to.equal(0);
      expect(user.childrenBv[0]).to.equal(0);
      expect(user.childrenBv[3]).to.equal(0);
    });

    it("does not credit BV when buyer is outside the upline subtree", async function () {
      const { core, usdt, twapAddress, yieldPoolAddress, fvAddress } = contracts;
      await setupCoreForTrading(core, {
        twapAddress,
        yieldPoolAddress,
        fvAddress,
      });

      await buildDeepLineTree();
      // Sibling under root (position 3), not under signers[5].
      await mockPurchase(core, usdt, signers[1], 1000, signers[0].address, 3);

      const uplineId = await core.getUserIdByAddress(signers[5].address);
      await advanceOneProtocolDay();

      await core.connect(signers[1]).calculateOrders(uplineId, [4]);

      const user = await core.getUserById(uplineId);
      expect(user.withdrawableCommission).to.equal(0);
    });

    it("prevent double-counts BV when the same order ids appear twice", async function () {
      const { core, twapAddress, yieldPoolAddress, fvAddress } = contracts;
      await setupCoreForTrading(core, {
        twapAddress,
        yieldPoolAddress,
        fvAddress,
      });
      const uplineId = await buildPairZeroTree();
      await advanceOneProtocolDay();

      await expect(core.connect(signers[1]).calculateOrders(uplineId, [4, 4, 5, 5])).to.be.revertedWith('Order with greater ID is already processed for this user.');
    });

    it("processes pair 0 once when order ids are unique", async function () {
      const { core, twapAddress, yieldPoolAddress, fvAddress } = contracts;
      await setupCoreForTrading(core, {
        twapAddress,
        yieldPoolAddress,
        fvAddress,
      });
      const uplineId = await buildPairZeroTree();
      await advanceOneProtocolDay();

      await core.connect(signers[1]).calculateOrders(uplineId, [4, 5]);

      const normal = await core.getUserById(uplineId);
      expect(normal.withdrawableCommission).to.equal(120n * 10n ** 6n);
    });

    it("earns more commission when all downline order ids are processed in order", async function () {
      const { core, twapAddress, yieldPoolAddress, fvAddress } = contracts;
      await setupCoreForTrading(core, {
        twapAddress,
        yieldPoolAddress,
        fvAddress,
      });

      const uplineId = await buildThreeLegTree();
      await advanceOneProtocolDay();

      await core.connect(signers[1]).calculateOrders(uplineId, [5, 6, 7]);

      const full = await core.getUserById(uplineId);
      expect(full.withdrawableCommission).to.equal(240n * 10n ** 6n);
      expect(full.withdrawableCommission).to.be.gt(120n * 10n ** 6n);
    });
  });

  describe("withdrawCommission", function () {
    async function buildPairZeroTree() {
      const { core, usdt } = contracts;
      await mockPurchase(core, usdt, signers[0], 100, zeroAddress, 0);
      await mockPurchase(core, usdt, signers[5], 100, signers[0].address, 0);
      await mockPurchase(core, usdt, signers[5], 100, zeroAddress, 0);
      await mockPurchase(core, usdt, signers[1], 1000, signers[5].address, 0);
      await mockPurchase(core, usdt, signers[2], 1000, signers[5].address, 1);
      return await core.getUserIdByAddress(signers[5].address);
    }

    it("reverts when amount exceeds withdrawable commission", async function () {
      const { core, twapAddress, yieldPoolAddress, fvAddress } = contracts;
      await setupCoreForTrading(core, {
        twapAddress,
        yieldPoolAddress,
        fvAddress,
      });

      const uplineId = await buildPairZeroTree();
      await advanceOneProtocolDay();
      await core.connect(signers[1]).calculateOrders(uplineId, [4, 5]);

      await expect(
        core.connect(signers[5]).withdrawCommission(121n * 10n ** 6n),
      ).to.be.revertedWith("Insufficient commission balance");
    });

    it("reverts when core payment token balance is insufficient", async function () {
      const { core } = contracts;

      const userWithBalance = {
        ...migrateUserDataMock[0],
        withdrawableCommission: 60n * 10n ** 6n,
      };
      await core.migrateUser([userWithBalance]);

      await expect(
        core.connect(signers[0]).withdrawCommission(60n * 10n ** 6n),
      ).to.be.revertedWith(
        "Insufficient balance in core. You can withdraw your commission after a purchase in system.",
      );
    });

    it("allows partial withdrawal and leaves remaining balance", async function () {
      const {
        core,
        usdt,
        coreAddress,
        twapAddress,
        yieldPoolAddress,
        fvAddress,
      } = contracts;
      await setupCoreForTrading(core, {
        twapAddress,
        yieldPoolAddress,
        fvAddress,
      });

      const uplineId = await buildPairZeroTree();
      await advanceOneProtocolDay();
      await core.connect(signers[1]).calculateOrders(uplineId, [4, 5]);

      await core.connect(signers[5]).withdrawCommission(60n * 10n ** 6n);

      const user = await core.getUserById(uplineId);
      expect(user.withdrawableCommission).to.equal(60n * 10n ** 6n);
      expect(await usdt.balanceOf(coreAddress)).to.be.gte(60n * 10n ** 6n);
    });
  });

  describe("weekly ARC", function () {
    async function setupArcWeek() {
      const {
        core,
        arc,
        usdt,
        coreAddress,
        twapAddress,
        yieldPoolAddress,
        fvAddress,
      } = contracts;

      await setupCoreForTrading(core, {
        twapAddress,
        yieldPoolAddress,
        fvAddress,
      });

      await mockPurchase(core, usdt, signers[0], 100, zeroAddress, 0);
      await mockPurchase(core, usdt, signers[1], 1000, signers[0].address, 0);
      await mockPurchase(core, usdt, signers[2], 1900, signers[0].address, 3);

      await arc.setMintOperator(coreAddress);
      await core.mintArc([signers[9].address, coreAddress], [parseEther("400"), parseEther("1")]);

      return { core, arc, coreAddress };
    }

    it("reverts mintWeeklyARC on the first day of the protocol week", async function () {
      const { core } = await setupArcWeek();
      await moveToFirstDayOfProtocolWeek();

      await expect(core.mintWeeklyARC()).to.be.revertedWith(
        "ARC calculation is not possible at the first day of week.",
      );
    });

    it("reverts when minting ARC twice for the same week", async function () {
      const { core } = await setupArcWeek();
      await networkHelpers.time.increase(7 * 86400);

      await core.mintWeeklyARC();
      await expect(core.mintWeeklyARC()).to.be.revertedWith(
        "ARC of this week is already minted.",
      );
    });

    it("reverts networker ARC claim without eligible week calculation", async function () {
      const { core } = await setupArcWeek();
      await networkHelpers.time.increase(7 * 86400);
      await core.mintWeeklyARC();

      await expect(
        core.connect(signers[0]).calculateNetworkerWeeklyARC(),
      ).to.be.revertedWith(
        "User hasn't calculated orders at the first day of the week.",
      );
    });

    it("reverts when networker claims ARC twice for the same week", async function () {
      const { core } = await setupArcWeek();
      await core.addManager(signers[1].address);

      await networkHelpers.time.increase(5 * 86400);
      await core.connect(signers[1]).calculateOrders(1, [1, 2, 3]);
      await networkHelpers.time.increase(2 * 86400);
      await core.mintWeeklyARC();

      await core.connect(signers[0]).calculateNetworkerWeeklyARC();
      await expect(
        core.connect(signers[0]).calculateNetworkerWeeklyARC(),
      ).to.be.revertedWith(
        "Networker has already calculated ARC for this week.",
      );
    });

    it("reverts when buyer claims user ARC twice for the same week", async function () {
      const { core } = await setupArcWeek();

      await networkHelpers.time.increase(7 * 86400);
      await core.mintWeeklyARC();

      await core.connect(signers[1]).calculateUserWeeklyArc();
      await expect(
        core.connect(signers[1]).calculateUserWeeklyArc(),
      ).to.be.revertedWith("User has already calculated ARC for this week.");
    });
  });

  describe("admin", function () {
    it("reverts when owner revokes themselves as manager", async function () {
      const { core } = contracts;

      await expect(
        core.connect(signers[1]).revokeManager(signers[1].address),
      ).to.be.revertedWith("User cannot revoke itself");
    });

    it("reverts when a non-owner manager calls revokeManager", async function () {
      const { core } = contracts;
      await core.connect(signers[1]).addManager(signers[2].address);

      await expect(
        core.connect(signers[2]).revokeManager(signers[1].address),
      ).to.be.revertedWithCustomError(core, "UnauthorizedAddress");
    });

    it("reverts address approval when new address is already registered", async function () {
      const { core } = contracts;

      await core.migrateUser([
        migrateUserDataMock[0],
        migrateUserDataMock[1],
      ]);

      await core
        .connect(signers[1])
        .requestChangeAddress(signers[0].address);

      await expect(
        core.connect(signers[0]).approveChangeAddress(2),
      ).to.be.revertedWithCustomError(core, "AddressAlreadyRegistered");
    });
  });
});
