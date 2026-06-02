import { expect } from "chai";
import { parseEther } from "ethers";
import hre from "hardhat";
import { zeroAddress } from "viem";
import { createCoreTestHelpers } from "../../test-helpers/core-helpers.js";
import { SnapshotRestorer } from "@nomicfoundation/hardhat-network-helpers/types";

const { ethers, networkHelpers } = await hre.network.create();
const signers = await ethers.getSigners();
const { deployContracts, migrateUserDataMock, mockPurchase } =
  createCoreTestHelpers(ethers, signers);

describe("DNMCore", function () {
  let snapshot: SnapshotRestorer;
  let contracts: Awaited<ReturnType<typeof deployContracts>>;
  before(async function () {
    contracts = await deployContracts();
    snapshot = await networkHelpers.takeSnapshot();
  });

  beforeEach(async function () {
    await snapshot.restore();
  });

  it("Change fee reciever address only one time", async function () {
    const { core } = contracts;
    await core.connect(signers[1]).changeFeeReceiverAddress(signers[1].address);

    await expect(
      core.connect(signers[1]).changeFeeReceiverAddress(signers[2].address),
    ).to.be.revertedWith("Fee receiver has already been transferred");
  });

  it("Change fee receiver only by owner", async function () {
    const { core } = contracts;
    await expect(
      core.changeFeeReceiverAddress(signers[1].address),
    ).to.be.revertedWithCustomError(core, "OwnableUnauthorizedAccount");
  });

  it("Transfer ownership only by owner only once", async function () {
    const { core } = contracts;
    await expect(
      core.connect(signers[1]).transferOwnership(signers[0].address),
    ).to.emit(core, "OwnershipTransferred");
    await expect(
      core.connect(signers[0]).transferOwnership(signers[1].address),
    ).to.be.revertedWith("Ownership has already been transferred");
  });

  it("Transfer ownership only by owner and not by deployer", async function () {
    const { core } = contracts;
    await expect(
      core.connect(signers[0]).transferOwnership(signers[0].address),
    ).to.be.revertedWithCustomError(core, "OwnableUnauthorizedAccount");
  });

  it("Addresses should be set only by deployer", async function () {
    const { core, fvAddress, twapAddress, yieldPoolAddress } = contracts;

    await core.setAddresses(twapAddress, yieldPoolAddress, fvAddress);

    await expect(
      core
        .connect(signers[1])
        .setAddresses(
          "0x0000000000000000000000000000000000000000",
          "0x0000000000000000000000000000000000000000",
          "0x0000000000000000000000000000000000000000",
        ),
    ).to.be.revertedWith("Only deployer is valid to operate in dev mode.");
  });

  it("Addresses should be set only in devMode", async function () {
    const { core } = contracts;

    await core.revokeDevMode();

    await expect(
      core.setAddresses(
        "0x0000000000000000000000000000000000000000",
        "0x0000000000000000000000000000000000000000",
        "0x0000000000000000000000000000000000000000",
      ),
    ).to.be.revertedWith("Developer mode is turned off");
  });

  it("User should be migrated", async function () {
    const { core } = contracts;

    await expect(
      core.migrateUser(
        [1, 2],
        [migrateUserDataMock[0], migrateUserDataMock[1]],
      ),
    ).to.emit(core, "UserMigrated");

    expect((await core.getUserById(1)).userAddress).to.equal(
      signers[0].address,
    );
    expect(await core.getUserIdByAddress(signers[0].address)).to.equal(1n);
  });

  it("User cannot be migrated after devMode", async function () {
    const { core } = contracts;

    await core.revokeDevMode();

    await expect(
      core.migrateUser([1], [migrateUserDataMock[0]]),
    ).to.be.revertedWith("Developer mode is turned off");
  });

  it("ARC mint should be reverted if mint operator is not set", async function () {
    const { core } = contracts;

    await expect(
      core.mintArc(signers[1].address, parseEther("1")),
    ).to.be.revertedWith("Only mint operator can mint");
  });

  it("ARC should be minted by core", async function () {
    const { arc, core, coreAddress } = contracts;

    await arc.setMintOperator(coreAddress);

    await expect(core.mintArc(signers[1].address, parseEther("1"))).to.emit(
      arc,
      "Transfer",
    );

    expect(await arc.balanceOf(signers[1].address)).to.be.equal(
      parseEther("1"),
    );
  });

  it("ARC should not be minted by core after devMode", async function () {
    const { arc, core, coreAddress } = contracts;

    await arc.setMintOperator(coreAddress);

    await core.revokeDevMode();

    await expect(
      core.mintArc(signers[1].address, parseEther("1")),
    ).to.be.revertedWith("Developer mode is turned off");
  });

  it("Order should be created and FV should be charged", async function () {
    const { core, usdt, fv, coreAddress, fvAddress } = contracts;

    await core.addWhiteListContract(signers[1].address);

    await core.setAddresses(
      "0x0000000000000000000000000000000000000000",
      "0x0000000000000000000000000000000000000000",
      fvAddress,
    );

    await usdt.connect(signers[1]).approve(coreAddress, 101 * 1e6);

    await expect(
      core.connect(signers[1]).createOrder(
        signers[1].address,
        zeroAddress,
        0,
        [
          {
            sellerAddress: "0x0000000000000000000000000000000000000001",
            bv: 100 * 1e6,
            sv: 50 * 1.6,
          },
        ],
        101 * 1e6,
      ),
    ).to.emit(core, "OrderCreated");

    expect(await usdt.balanceOf(fvAddress)).to.be.equal(20 * 1e6);
    expect(await usdt.balanceOf(signers[0].address)).to.be.equal(1 * 1e6);
    expect(await fv.monthlyFv(18)).to.be.equal(20 * 1e6);

    expect(
      await core.getSellerIdByAddress(
        "0x0000000000000000000000000000000000000001",
      ),
    ).not.be.equal(0);
    expect(await core.getUserIdByAddress(signers[1].address)).not.be.equal(0);
  });

  it("Order should not be created if total amount is less than BV summation", async function () {
    const { core, usdt, coreAddress, fvAddress } = contracts;

    await core.addWhiteListContract(signers[1].address);

    await core.setAddresses(
      "0x0000000000000000000000000000000000000000",
      "0x0000000000000000000000000000000000000000",
      fvAddress,
    );

    await usdt.connect(signers[1]).approve(coreAddress, 101 * 1e6);

    await expect(
      core.connect(signers[1]).createOrder(
        signers[1].address,
        zeroAddress,
        0,
        [
          {
            sellerAddress: "0x0000000000000000000000000000000000000001",
            bv: 100 * 1e6,
            sv: 50 * 1.6,
          },
          {
            sellerAddress: "0x0000000000000000000000000000000000000001",
            bv: 100 * 1e6,
            sv: 50 * 1.6,
          },
        ],
        199 * 1e6,
      ),
    ).to.be.rejectedWith("Provided amount is less than order business amounts");
  });

  it("Left normal node should not be active before 200 BV", async function () {
    const { core, usdt, fvAddress, coreAddress } = contracts;
    await core.addWhiteListContract(signers[1].address);

    await core.setAddresses(
      "0x0000000000000000000000000000000000000000",
      "0x0000000000000000000000000000000000000000",
      fvAddress,
    );

    await mockPurchase(core, usdt, signers[0], 100, zeroAddress, 0);
    await usdt.connect(signers[1]).approve(coreAddress, 101 * 1e6);
    await expect(
      core.connect(signers[1]).createOrder(
        signers[1].address,
        signers[0].address,
        1,
        [
          {
            sellerAddress: "0x0000000000000000000000000000000000000001",
            bv: 100 * 1e6,
            sv: 50 * 1.6,
          },
        ],
        101 * 1e6,
      ),
    ).to.be.revertedWithCustomError(core, "ParentInsufficientBVForPosition");

    await mockPurchase(core, usdt, signers[0], 100, zeroAddress, 0);
    await usdt.connect(signers[1]).approve(coreAddress, 101 * 1e6);
    await expect(
      core.connect(signers[1]).createOrder(
        signers[1].address,
        signers[0].address,
        1,
        [
          {
            sellerAddress: "0x0000000000000000000000000000000000000001",
            bv: 100 * 1e6,
            sv: 50 * 1.6,
          },
        ],
        101 * 1e6,
      ),
    ).to.emit(core, "OrderCreated");
  });

  it("Right normal node should not be active before 300 BV", async function () {
    const { core, usdt, fvAddress, coreAddress } = contracts;
    await core.addWhiteListContract(signers[1].address);

    await core.setAddresses(
      "0x0000000000000000000000000000000000000000",
      "0x0000000000000000000000000000000000000000",
      fvAddress,
    );

    await mockPurchase(core, usdt, signers[0], 200, zeroAddress, 0);
    await usdt.connect(signers[1]).approve(coreAddress, 101 * 1e6);
    await expect(
      core.connect(signers[1]).createOrder(
        signers[1].address,
        signers[0].address,
        2,
        [
          {
            sellerAddress: "0x0000000000000000000000000000000000000001",
            bv: 100 * 1e6,
            sv: 50 * 1.6,
          },
        ],
        101 * 1e6,
      ),
    ).to.be.revertedWithCustomError(core, "ParentInsufficientBVForPosition");

    await mockPurchase(core, usdt, signers[0], 100, zeroAddress, 0);
    await usdt.connect(signers[1]).approve(coreAddress, 101 * 1e6);
    await expect(
      core.connect(signers[1]).createOrder(
        signers[1].address,
        signers[0].address,
        2,
        [
          {
            sellerAddress: "0x0000000000000000000000000000000000000001",
            bv: 100 * 1e6,
            sv: 50 * 1.6,
          },
        ],
        101 * 1e6,
      ),
    ).to.emit(core, "OrderCreated");
  });

  it("Owner can add manager", async function () {
    const { core } = contracts;

    await core.connect(signers[1]).addManager(signers[2].address);

    expect(await core.isManager(signers[2].address)).to.be.true;
  });

  it("Deployer can add manager in dev mode", async function () {
    const { core } = contracts;

    await core.addManager(signers[2].address);

    expect(await core.isManager(signers[2].address)).to.be.true;
  });

  it("Deployer cannot add manager after dev mode", async function () {
    const { core } = contracts;

    await core.revokeDevMode();
    await expect(
      core.addManager(signers[2].address),
    ).to.be.revertedWithCustomError(core, "UnauthorizedAddress");
  });

  it("Owner can add manager after dev mode", async function () {
    const { core } = contracts;

    await core.revokeDevMode();
    await core.connect(signers[1]).addManager(signers[2].address);

    expect(await core.isManager(signers[2].address)).to.be.true;
  });

  it("Owner can revoke manager", async function () {
    const { core } = contracts;

    await core.connect(signers[1]).addManager(signers[2].address);
    expect(await core.isManager(signers[2].address)).to.be.true;

    await core.connect(signers[1]).revokeManager(signers[2].address);
    expect(await core.isManager(signers[2].address)).to.be.false;
  });

  it("Deployer can revoke manager in dev mode", async function () {
    const { core } = contracts;

    await core.addManager(signers[2].address);
    expect(await core.isManager(signers[2].address)).to.be.true;

    await core.revokeManager(signers[2].address);
    expect(await core.isManager(signers[2].address)).to.be.false;
  });

  it("Deployer cannot revoke manager after dev mode", async function () {
    const { core } = contracts;

    await core.revokeDevMode();
    await expect(
      core.revokeManager(signers[2].address),
    ).to.be.revertedWithCustomError(core, "UnauthorizedAddress");
  });

  it("Owner can revoke manager after dev mode", async function () {
    const { core } = contracts;

    await core.revokeDevMode();
    await core.connect(signers[1]).addManager(signers[2].address);
    expect(await core.isManager(signers[2].address)).to.be.true;

    await core.connect(signers[1]).revokeManager(signers[2].address);
    expect(await core.isManager(signers[2].address)).to.be.false;
  });

  it("Not registered user cannot request for address change", async function () {
    const { core } = contracts;

    await expect(
      core.requestChangeAddress("0x0000000000000000000000000000000000000001"),
    ).to.be.revertedWithCustomError(core, "UserNotRegistered");
  });

  it("Registered user can request for address change", async function () {
    const { core } = contracts;

    await core.migrateUser([1], [migrateUserDataMock[0]]);

    await expect(
      core.requestChangeAddress("0x0000000000000000000000000000000000000001"),
    ).to.emit(core, "AddressChangeRequested");
  });

  it("Registered user can update the request for address change", async function () {
    const { core } = contracts;

    await core.migrateUser([1], [migrateUserDataMock[0]]);

    await expect(
      core.requestChangeAddress("0x0000000000000000000000000000000000000001"),
    ).to.emit(core, "AddressChangeRequested");
    await expect(
      core.requestChangeAddress("0x0000000000000000000000000000000000000002"),
    )
      .to.emit(core, "AddressChangeRequestCancelled")
      .to.emit(core, "AddressChangeRequested");
  });

  it("Registered user can cancel the request for address change", async function () {
    const { core } = contracts;

    await core.migrateUser(
      [1, 2],
      [migrateUserDataMock[0], migrateUserDataMock[1]],
    );

    await expect(
      core.requestChangeAddress("0x0000000000000000000000000000000000000001"),
    ).to.emit(core, "AddressChangeRequested");
    await expect(core.cancelChangeAddressRequest()).to.emit(
      core,
      "AddressChangeRequestCancelled",
    );
    await expect(
      core.connect(signers[1]).approveChangeAddress(1),
    ).to.be.revertedWith(
      "Provided user id hasn't requested for address change.",
    );
  });

  it("Direct child of root node can accept address change", async function () {
    const { core } = contracts;

    await core.migrateUser(
      [1, 2],
      [migrateUserDataMock[0], migrateUserDataMock[1]],
    );

    await core.requestChangeAddress(
      "0x0000000000000000000000000000000000000001",
    );
    await expect(
      core.connect(signers[0]).approveChangeAddress(1),
    ).to.be.revertedWith(
      "Only the 1st position of the root user can approve change address",
    );
    await expect(core.connect(signers[1]).approveChangeAddress(1)).to.emit(
      core,
      "AddressChanged",
    );
    expect((await core.getUserById(1)).userAddress).to.equal(
      "0x0000000000000000000000000000000000000001",
    );
    expect(
      await core.getUserIdByAddress(
        "0x0000000000000000000000000000000000000001",
      ),
    ).to.equal(1);
  });

  it("Direct leader of all nodes can accept address change", async function () {
    const { core } = contracts;

    await core.migrateUser(
      [1, 2],
      [migrateUserDataMock[0], migrateUserDataMock[1]],
    );

    await core
      .connect(signers[1])
      .requestChangeAddress("0x0000000000000000000000000000000000000001");
    await expect(
      core.connect(signers[1]).approveChangeAddress(2),
    ).to.be.revertedWith(
      "Only direct parent of the user can approve changing address.",
    );
    await expect(core.connect(signers[0]).approveChangeAddress(2)).to.emit(
      core,
      "AddressChanged",
    );
    expect((await core.getUserById(2)).userAddress).to.equal(
      "0x0000000000000000000000000000000000000001",
    );
    expect(
      await core.getUserIdByAddress(
        "0x0000000000000000000000000000000000000001",
      ),
    ).to.equal(2);
  });

  it("Registered user cannot cancel change address request if there's not any", async function () {
    const { core } = contracts;

    await core.migrateUser([1], [migrateUserDataMock[0]]);

    await expect(
      core.cancelChangeAddressRequest(),
    ).to.be.revertedWithCustomError(core, "UserNotRequestedChangeAddress");
  });

  it("Not registered user cannot cancel change address request", async function () {
    const { core } = contracts;

    await expect(
      core.cancelChangeAddressRequest(),
    ).to.be.revertedWithCustomError(core, "UserNotRegistered");
  });

  it("Get current month should work properly", async function () {
    const { core } = contracts;

    expect(await core.getCurrentMonthNo()).to.equal(18n);
  });

  it("Orders should be calculated, steps should be set, FV should be added and commission should be withdrawn", async function () {
    const { core, usdt, fv, coreAddress, fvAddress } = contracts;

    await core.addWhiteListContract(signers[1].address);

    await core.setAddresses(
      "0x0000000000000000000000000000000000000000",
      "0x0000000000000000000000000000000000000000",
      fvAddress,
    );

    //First purchase
    await usdt.connect(signers[1]).approve(coreAddress, 101 * 1e6);

    await expect(
      core.connect(signers[1]).createOrder(
        signers[5].address,
        zeroAddress,
        0,
        [
          {
            sellerAddress: signers[9],
            bv: 100 * 1e6,
            sv: 50 * 1.6,
          },
        ],
        101 * 1e6,
      ),
    ).to.emit(core, "OrderCreated");

    //Second purchase
    await usdt.connect(signers[1]).approve(coreAddress, 1010 * 1e6);

    await expect(
      core.connect(signers[1]).createOrder(
        signers[1].address,
        signers[5].address,
        0,
        [
          {
            sellerAddress: signers[9],
            bv: 1000 * 1e6,
            sv: 50 * 1.6,
          },
        ],
        1010 * 1e6,
      ),
    ).to.emit(core, "OrderCreated");

    //Third purchase
    await usdt.connect(signers[1]).approve(coreAddress, 1010 * 1e6);

    await expect(
      core.connect(signers[1]).createOrder(
        signers[2].address,
        signers[5].address,
        3,
        [
          {
            sellerAddress: signers[9],
            bv: 1000 * 1e6,
            sv: 50 * 1.6,
          },
        ],
        1010 * 1e6,
      ),
    ).to.emit(core, "OrderCreated");

    const userId = await core.getUserIdByAddress(signers[5].address);

    // Wait a day
    await networkHelpers.time.increase(86400);

    await core.connect(signers[1]).calculateOrders(userId, [1, 2, 3]);

    const user = await core.getUserById(userId);

    const dayNumber = Math.floor(
      (Math.floor(new Date().getTime() / 1000) - 1762732800) / 86400,
    );

    expect(user.superNodeTotalSteps).to.equal(2n);
    expect(user.withdrawableCommission).to.equal(120 * 1e6);
    expect(user.lastCalculatedOrder).to.equal(3n);
    expect(user.fvEntranceMonth).to.equal(18n);
    expect(user.fvEntranceShare).to.equal(2n);
    expect(await core.globalDailySteps(dayNumber)).to.equal(2n);
    expect(await core.globalDailySteps(dayNumber - 1)).to.equal(0n);
    expect(await core.userDailySteps(userId, dayNumber, 0)).to.equal(0n);
    expect(await core.userDailySteps(userId, dayNumber, 1)).to.equal(0n);
    expect(await core.userDailySteps(userId, dayNumber, 2)).to.equal(2n);

    await expect(
      core.connect(signers[5]).withdrawCommission(120 * 1e6),
    ).to.emit(core, "CommissionWithdrawn");
    expect(await usdt.balanceOf(signers[5].address)).to.equal(120 * 1e6);

    const userShare = await fv.getUserShareInPaymentToken(userId, 18);

    expect(userShare).to.equal(420 * 1e6);

    // wait a month
    await networkHelpers.time.increase(86400 * 30);

    await expect(fv.connect(signers[5]).withdrawFastValueShare(18)).to.emit(
      fv,
      "MonthlyFastValueWithdrawn",
    );
    expect(await usdt.balanceOf(signers[5].address)).to.equal(
      (120 + 420) * 1e6,
    );
    expect(await fv.getUserShareInPaymentToken(userId, 18)).to.equal(0);
  });

  it("Fv entrance with .5 share.", async function () {
    const { core, usdt, fv, coreAddress, fvAddress } = contracts;

    await core.addWhiteListContract(signers[1].address);

    await core.setAddresses(
      "0x0000000000000000000000000000000000000000",
      "0x0000000000000000000000000000000000000000",
      fvAddress,
    );

    //First purchase
    await mockPurchase(core, usdt, signers[5], 101, zeroAddress, 0);

    //Wait a month
    await networkHelpers.time.increase(30 * 86400);

    //Second purchase
    await mockPurchase(core, usdt, signers[1], 1010, signers[5].address, 0);

    //Third purchase
    await mockPurchase(core, usdt, signers[2], 1010, signers[5].address, 3);

    const userId = await core.getUserIdByAddress(signers[5].address);

    // Wait a day
    await networkHelpers.time.increase(86400);

    await core.connect(signers[1]).calculateOrders(userId, [1, 2, 3]);

    let user = await core.getUserById(userId);

    expect(user.fvEntranceMonth).to.equal(0);
    expect(user.fvEntranceShare).to.equal(0);

    await mockPurchase(core, usdt, signers[5], 100, zeroAddress, 0);
    await networkHelpers.time.increase(86400);
    await core.connect(signers[1]).calculateOrders(userId, [4]);
    user = await core.getUserById(userId);

    expect(user.fvEntranceMonth).to.equal(0);
    expect(user.fvEntranceShare).to.equal(0);

    await mockPurchase(core, usdt, signers[5], 20, zeroAddress, 0);
    await networkHelpers.time.increase(86400);
    await core.connect(signers[1]).calculateOrders(userId, [5]);
    user = await core.getUserById(userId);

    expect(user.fvEntranceMonth).to.equal(19n);
    expect(user.fvEntranceShare).to.equal(1n);
    expect(await fv.getUserShare(userId, 19n)).to.equal(1);
    expect(await fv.monthlyTotalShares(19n)).to.equal(1);
  });

  it("Fv continue with .5 share till one year", async function () {
    const { core, usdt, fv, coreAddress, fvAddress } = contracts;

    await core.addWhiteListContract(signers[1].address);

    await core.setAddresses(
      "0x0000000000000000000000000000000000000000",
      "0x0000000000000000000000000000000000000000",
      fvAddress,
    );

    //First purchase
    await mockPurchase(core, usdt, signers[5], 101, zeroAddress, 0);

    //Wait a month
    await networkHelpers.time.increase(30 * 86400);

    //Second purchase
    await mockPurchase(core, usdt, signers[1], 1010, signers[5].address, 0);

    //Third purchase
    await mockPurchase(core, usdt, signers[2], 1010, signers[5].address, 3);

    const userId = await core.getUserIdByAddress(signers[5].address);

    await networkHelpers.time.increase(86400);

    await core.connect(signers[1]).calculateOrders(userId, [1, 2, 3]);

    await mockPurchase(core, usdt, signers[5], 120, zeroAddress, 0);
    await networkHelpers.time.increase(86400);
    await core.connect(signers[1]).calculateOrders(userId, [4]);

    await mockPurchase(core, usdt, signers[5], 144, zeroAddress, 0);

    expect(await fv.getUserShare(userId, 19n)).to.equal(1);
    expect(await fv.monthlyTotalShares(19n)).to.equal(1);
    expect(await fv.getUserShare(userId, 20n)).to.equal(1);
    expect(await fv.monthlyTotalShares(20n)).to.equal(1);
    expect(await fv.getUserShare(userId, 21n)).to.equal(0);
    expect(await fv.monthlyTotalShares(21n)).to.equal(0);

    await mockPurchase(core, usdt, signers[5], 4486, zeroAddress, 0);

    for (let i = 0; i < 12; i++) {
      expect(await fv.getUserShare(userId, 19 + i)).to.equal(1);
      expect(await fv.monthlyTotalShares(19 + i)).to.equal(1);
    }

    await mockPurchase(core, usdt, signers[5], 1070, zeroAddress, 0);
    expect(await fv.getUserShare(userId, 31)).to.equal(0);
    expect(await fv.monthlyTotalShares(31)).to.equal(0);
  });

  it("Fv should not continue if one month passed without coverage", async function () {
    const { core, usdt, fv, coreAddress, fvAddress } = contracts;

    await core.addWhiteListContract(signers[1].address);

    await core.setAddresses(
      "0x0000000000000000000000000000000000000000",
      "0x0000000000000000000000000000000000000000",
      fvAddress,
    );

    //First purchase
    await mockPurchase(core, usdt, signers[5], 101, zeroAddress, 0);

    //Wait a month
    await networkHelpers.time.increase(30 * 86400);

    //Second purchase
    await mockPurchase(core, usdt, signers[1], 1010, signers[5].address, 0);

    //Third purchase
    await mockPurchase(core, usdt, signers[2], 1010, signers[5].address, 3);

    const userId = await core.getUserIdByAddress(signers[5].address);

    await networkHelpers.time.increase(86400);

    await core.connect(signers[1]).calculateOrders(userId, [1, 2, 3]);

    await mockPurchase(core, usdt, signers[5], 120, zeroAddress, 0);
    await networkHelpers.time.increase(86400);
    await core.connect(signers[1]).calculateOrders(userId, [4]);

    await mockPurchase(core, usdt, signers[5], 144, zeroAddress, 0);

    expect(await fv.getUserShare(userId, 19n)).to.equal(1);
    expect(await fv.monthlyTotalShares(19n)).to.equal(1);
    expect(await fv.getUserShare(userId, 20n)).to.equal(1);
    expect(await fv.monthlyTotalShares(20n)).to.equal(1);
    expect(await fv.getUserShare(userId, 21n)).to.equal(0);
    expect(await fv.monthlyTotalShares(21n)).to.equal(0);

    await networkHelpers.time.increase(90 * 86400);

    await mockPurchase(core, usdt, signers[5], 4486, zeroAddress, 0);

    for (let i = 2; i < 12; i++) {
      expect(await fv.getUserShare(userId, 19 + i)).to.equal(0);
      expect(await fv.monthlyTotalShares(19 + i)).to.equal(0);
    }
  });

  it("Fv continue with 1 share till one year", async function () {
    const { core, usdt, fv, coreAddress, fvAddress } = contracts;

    await core.addWhiteListContract(signers[1].address);

    await core.setAddresses(
      "0x0000000000000000000000000000000000000000",
      "0x0000000000000000000000000000000000000000",
      fvAddress,
    );

    //First purchase
    await mockPurchase(core, usdt, signers[5], 101, zeroAddress, 0);

    //Second purchase
    await mockPurchase(core, usdt, signers[1], 1010, signers[5].address, 0);

    //Third purchase
    await mockPurchase(core, usdt, signers[2], 1010, signers[5].address, 3);

    const userId = await core.getUserIdByAddress(signers[5].address);

    await networkHelpers.time.increase(86400);

    await core.connect(signers[1]).calculateOrders(userId, [1, 2, 3]);

    await mockPurchase(core, usdt, signers[5], 120, zeroAddress, 0);
    await networkHelpers.time.increase(86400);
    await core.connect(signers[1]).calculateOrders(userId, [4]);

    expect(await fv.getUserShare(userId, 18n)).to.equal(2);
    expect(await fv.monthlyTotalShares(18n)).to.equal(2);
    expect(await fv.getUserShare(userId, 19n)).to.equal(2);
    expect(await fv.monthlyTotalShares(19n)).to.equal(2);
    expect(await fv.getUserShare(userId, 20n)).to.equal(0);
    expect(await fv.monthlyTotalShares(20n)).to.equal(0);

    await mockPurchase(core, usdt, signers[5], 3739, zeroAddress, 0);

    for (let i = 0; i < 12; i++) {
      expect(await fv.getUserShare(userId, 18 + i)).to.equal(2);
      expect(await fv.monthlyTotalShares(18 + i)).to.equal(2);
    }

    await mockPurchase(core, usdt, signers[5], 1070, zeroAddress, 0);
    expect(await fv.getUserShare(userId, 31)).to.equal(0);
    expect(await fv.monthlyTotalShares(31)).to.equal(0);
  });

  it("ARC for the week should be minted", async function () {
    const {
      core,
      arc,
      usdt,
      coreAddress,
      twapAddress,
      yieldPoolAddress,
      fvAddress,
    } = contracts;

    await core.addWhiteListContract(signers[1].address);

    await core.setAddresses(twapAddress, yieldPoolAddress, fvAddress);

    await mockPurchase(core, usdt, signers[0], 100, zeroAddress, 0);
    await mockPurchase(core, usdt, signers[1], 1000, signers[0].address, 0);
    await mockPurchase(core, usdt, signers[2], 1900, signers[0].address, 3);

    await arc.setMintOperator(coreAddress);
    await core.mintArc(signers[0].address, parseEther("400"));
    await core.mintArc(coreAddress, parseEther("1"));

    await networkHelpers.time.increase(7 * 86400);

    await core.mintWeeklyARC();

    const coreArcBalance = await arc.balanceOf(coreAddress);
    expect(coreArcBalance - 6800513429000000000n).to.lessThan(100000000);
  });

  it("Networker should be able to withdraw ARC share", async function () {
    const {
      core,
      arc,
      usdt,
      coreAddress,
      twapAddress,
      yieldPoolAddress,
      fvAddress,
    } = contracts;

    await core.addWhiteListContract(signers[1].address);

    await core.setAddresses(twapAddress, yieldPoolAddress, fvAddress);

    await core.addManager(signers[1].address);

    await mockPurchase(core, usdt, signers[0], 100, zeroAddress, 0);
    await mockPurchase(core, usdt, signers[1], 1000, signers[0].address, 0);
    await mockPurchase(core, usdt, signers[2], 1900, signers[0].address, 3);

    await arc.setMintOperator(coreAddress);
    await core.mintArc(signers[9].address, parseEther("400"));
    await core.mintArc(coreAddress, parseEther("1"));

    //Always should be set to next monday
    await networkHelpers.time.increase(6 * 86400);

    await core.connect(signers[1]).calculateOrders(1, [1, 2, 3]);

    await networkHelpers.time.increase(86400);

    await core.mintWeeklyARC();

    await core.connect(signers[0]).calculateNetworkerWeeklyARC();

    const calculated = 6800513429000000000n / 2n;

    const networkerBalance = await arc.balanceOf(signers[0]);

    expect(networkerBalance - calculated).to.lessThan(100000000);
  });

  it("Buyer should be able to withdraw ARC share", async function () {
    const {
      core,
      arc,
      usdt,
      coreAddress,
      twapAddress,
      yieldPoolAddress,
      fvAddress,
    } = contracts;

    await core.addWhiteListContract(signers[1].address);

    await core.setAddresses(twapAddress, yieldPoolAddress, fvAddress);

    await core.addManager(signers[1].address);

    await mockPurchase(core, usdt, signers[0], 100, zeroAddress, 0);
    await mockPurchase(core, usdt, signers[1], 1000, signers[0].address, 0);
    await mockPurchase(core, usdt, signers[2], 1900, signers[0].address, 3);

    await arc.setMintOperator(coreAddress);
    await core.mintArc(signers[9].address, parseEther("400"));
    await core.mintArc(coreAddress, parseEther("1"));

    await networkHelpers.time.increase(4 * 86400);

    await core.connect(signers[1]).calculateOrders(1, [1, 2, 3]);

    await networkHelpers.time.increase(3 * 86400);

    await core.mintWeeklyARC();

    await core.connect(signers[1]).calculateUserWeeklyArc();

    const calculated = (6800513429000000000n * 4n) / 10n / 3n;

    const buyerBalance = await arc.balanceOf(signers[1]);

    expect(buyerBalance - calculated).to.lessThan(100000000);
  });

  it("Seller should be able to withdraw ARC share", async function () {
    const {
      core,
      arc,
      usdt,
      coreAddress,
      twapAddress,
      yieldPoolAddress,
      fvAddress,
    } = contracts;

    await core.addWhiteListContract(signers[1].address);

    await core.setAddresses(twapAddress, yieldPoolAddress, fvAddress);

    await core.addManager(signers[1].address);

    await mockPurchase(core, usdt, signers[0], 100, zeroAddress, 0);
    await mockPurchase(core, usdt, signers[1], 1000, signers[0].address, 0);
    await mockPurchase(core, usdt, signers[2], 1900, signers[0].address, 3);

    await arc.setMintOperator(coreAddress);
    await core.mintArc(signers[5].address, parseEther("400"));
    await core.mintArc(coreAddress, parseEther("1"));

    await networkHelpers.time.increase(4 * 86400);

    await core.connect(signers[1]).calculateOrders(1, [1, 2, 3]);

    await networkHelpers.time.increase(3 * 86400);

    await core.mintWeeklyARC();

    await core.connect(signers[9]).calculateSellerWeeklyArc();

    const calculated = 6800513429000000000n / 10n;

    const sellerBalance = await arc.balanceOf(signers[9]);

    expect(sellerBalance - calculated).to.lessThan(100000000);
  });
});
