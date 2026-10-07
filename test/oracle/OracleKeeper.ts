import assert from "node:assert/strict";
import { describe, it } from "node:test";

import { network } from "hardhat";
import { walletActions } from "viem";

describe("OracleKeeper", async function () {
  const connection = await network.connect();
  const { viem, networkHelpers } = connection as typeof connection & {
    networkHelpers: {
      time: { increase: (seconds: number | bigint) => Promise<void> };
    };
  };
  const publicClient = (await viem.getPublicClient()).extend(walletActions);
  const [owner, forwarder, otherForwarder, attacker] = await publicClient.getAddresses();

  async function deploy() {
    const oracle = await viem.deployContract("MockTwapOracle");
    const keeper = await viem.deployContract("OracleKeeper", [oracle.address]);
    return { oracle, keeper };
  }

  it("owner can add and remove forwarders", async function () {
    const { keeper } = await deploy();

    await keeper.write.setForwarder([forwarder, true], { account: owner });
    assert.equal(await keeper.read.allowedForwarders([forwarder]), true);

    await keeper.write.setForwarder([forwarder, false], { account: owner });
    assert.equal(await keeper.read.allowedForwarders([forwarder]), false);
  });

  it("reverts updateOracle when caller is not an allowed forwarder", async function () {
    const { keeper } = await deploy();
    await keeper.write.setForwarder([forwarder, true], { account: owner });

    await viem.assertions.revertWithCustomError(
      keeper.write.updateOracle({ account: attacker }),
      keeper,
      "NotForwarder",
    );
  });

  it("allowed forwarder triggers oracle.update via updateOracle", async function () {
    const { oracle, keeper } = await deploy();
    await keeper.write.setForwarder([forwarder, true], { account: owner });

    await keeper.write.updateOracle({ account: forwarder });

    assert.equal(await oracle.read.updateCount(), 1n);
    assert.equal(await keeper.read.lastTimeStamp() > 0n, true);
  });

  it("reverts when called again before MIN_INTERVAL", async function () {
    const { keeper } = await deploy();
    await keeper.write.setForwarder([forwarder, true], { account: owner });
    await keeper.write.updateOracle({ account: forwarder });

    await viem.assertions.revertWithCustomError(
      keeper.write.updateOracle({ account: forwarder }),
      keeper,
      "UpdateTooSoon",
    );
  });

  it("allows another update after MIN_INTERVAL", async function () {
    const { oracle, keeper } = await deploy();
    const minInterval = await keeper.read.MIN_INTERVAL();
    await keeper.write.setForwarder([forwarder, true], { account: owner });
    await keeper.write.updateOracle({ account: forwarder });

    await networkHelpers.time.increase(minInterval);
    await keeper.write.updateOracle({ account: forwarder });

    assert.equal(await oracle.read.updateCount(), 2n);
  });

  it("supports multiple allowed forwarders", async function () {
    const { oracle, keeper } = await deploy();
    await keeper.write.setForwarder([forwarder, true], { account: owner });
    await keeper.write.setForwarder([otherForwarder, true], { account: owner });

    await keeper.write.updateOracle({ account: otherForwarder });
    assert.equal(await oracle.read.updateCount(), 1n);
  });

  it("canUpdate is true before first update when oracle is ready", async function () {
    const { keeper } = await deploy();
    assert.equal(await keeper.read.canUpdate(), true);
  });

  it("canUpdate is false right after a successful update", async function () {
    const { keeper } = await deploy();
    await keeper.write.setForwarder([forwarder, true], { account: owner });
    await keeper.write.updateOracle({ account: forwarder });
    assert.equal(await keeper.read.canUpdate(), false);
  });
});
