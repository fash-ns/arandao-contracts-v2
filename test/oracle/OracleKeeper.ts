import assert from "node:assert/strict";
import { describe, it } from "node:test";

import { network } from "hardhat";
import { walletActions } from "viem";

const FIVE_DAYS = 5n * 24n * 60n * 60n;
const IRECEIVER_INTERFACE_ID = "0x805f2132"; // type(IReceiver).interfaceId = onReport(bytes,bytes)
const IERC165_INTERFACE_ID = "0x01ffc9a7";

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

  it("supports IReceiver and IERC165", async function () {
    const { keeper } = await deploy();
    assert.equal(await keeper.read.supportsInterface([IRECEIVER_INTERFACE_ID]), true);
    assert.equal(await keeper.read.supportsInterface([IERC165_INTERFACE_ID]), true);
  });

  it("owner can add and remove forwarders", async function () {
    const { keeper } = await deploy();

    await keeper.write.setForwarder([forwarder, true], { account: owner });
    assert.equal(await keeper.read.allowedForwarders([forwarder]), true);

    await keeper.write.setForwarder([forwarder, false], { account: owner });
    assert.equal(await keeper.read.allowedForwarders([forwarder]), false);
  });

  it("reverts onReport when caller is not an allowed forwarder", async function () {
    const { keeper } = await deploy();
    await keeper.write.setForwarder([forwarder, true], { account: owner });

    await viem.assertions.revertWithCustomError(
      keeper.write.onReport(["0x", "0x"], { account: attacker }),
      keeper,
      "NotForwarder",
    );
  });

  it("allowed forwarder triggers oracle.update via onReport", async function () {
    const { oracle, keeper } = await deploy();
    await keeper.write.setForwarder([forwarder, true], { account: owner });

    await keeper.write.onReport(["0x", "0x"], { account: forwarder });

    assert.equal(await oracle.read.updateCount(), 1n);
    assert.equal(await keeper.read.lastTimeStamp() > 0n, true);
  });

  it("reverts when called again before MIN_INTERVAL", async function () {
    const { keeper } = await deploy();
    await keeper.write.setForwarder([forwarder, true], { account: owner });
    await keeper.write.onReport(["0x", "0x"], { account: forwarder });

    await viem.assertions.revertWithCustomError(
      keeper.write.onReport(["0x", "0x"], { account: forwarder }),
      keeper,
      "UpdateTooSoon",
    );
  });

  it("allows another update after MIN_INTERVAL", async function () {
    const { oracle, keeper } = await deploy();
    await keeper.write.setForwarder([forwarder, true], { account: owner });
    await keeper.write.onReport(["0x", "0x"], { account: forwarder });

    await networkHelpers.time.increase(FIVE_DAYS);
    await keeper.write.onReport(["0x", "0x"], { account: forwarder });

    assert.equal(await oracle.read.updateCount(), 2n);
  });

  it("supports multiple allowed forwarders", async function () {
    const { oracle, keeper } = await deploy();
    await keeper.write.setForwarder([forwarder, true], { account: owner });
    await keeper.write.setForwarder([otherForwarder, true], { account: owner });

    await keeper.write.onReport(["0x", "0x"], { account: otherForwarder });
    assert.equal(await oracle.read.updateCount(), 1n);
  });
});
