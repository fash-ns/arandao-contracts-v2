import assert from "node:assert/strict";
import { describe, it } from "node:test";

import { network } from "hardhat";
import { concatHex, encodeAbiParameters, padHex, parseAbiParameters, walletActions } from "viem";

const IRECEIVER_INTERFACE_ID = "0x805f2132"; // type(IReceiver).interfaceId = onReport(bytes,bytes)
const IERC165_INTERFACE_ID = "0x01ffc9a7";

/** Production KeystoneForwarder delivers 64-byte metadata (62-byte identity + reportId). */
function fakeCreMetadata(): `0x${string}` {
  const workflowId = padHex("0x01", { size: 32 });
  const workflowName = padHex("0x02", { size: 10 });
  const workflowOwner = padHex("0x03", { size: 20 });
  const reportId = "0x0000" as `0x${string}`;
  return concatHex([workflowId, workflowName, workflowOwner, reportId]);
}

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

  async function deployWithMockKeystone() {
    const oracle = await viem.deployContract("MockTwapOracle");
    const keeper = await viem.deployContract("OracleKeeper", [oracle.address]);
    const keystone = await viem.deployContract("MockKeystoneForwarder");
    await keeper.write.setForwarder([keystone.address, true], { account: owner });
    return { oracle, keeper, keystone };
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
    const minInterval = await keeper.read.MIN_INTERVAL();
    await keeper.write.setForwarder([forwarder, true], { account: owner });
    await keeper.write.onReport(["0x", "0x"], { account: forwarder });

    await networkHelpers.time.increase(minInterval);
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

  // ─── CRE / Keystone delivery path ───────────────────────────────────────────

  it("CRE path: MockKeystoneForwarder ERC165-probes then routes onReport", async function () {
    const { oracle, keeper, keystone } = await deployWithMockKeystone();
    const metadata = fakeCreMetadata();
    assert.equal(metadata.length, 2 + 64 * 2); // 0x + 64 bytes hex

    // Empty report matches a trigger-only CRE writeReport payload.
    await keystone.write.route([keeper.address, metadata, "0x"]);

    assert.equal(await oracle.read.updateCount(), 1n);
    assert.equal(await keeper.read.canUpdate(), false);
  });

  it("CRE path: accepts ABI-encoded report bytes like writeReport()", async function () {
    const { oracle, keeper, keystone } = await deployWithMockKeystone();
    const report = encodeAbiParameters(parseAbiParameters("uint256"), [0n]);

    await keystone.write.route([keeper.address, fakeCreMetadata(), report]);
    assert.equal(await oracle.read.updateCount(), 1n);
  });

  it("CRE path: rejects route when consumer is not whitelisted as forwarder", async function () {
    const { oracle, keeper } = await deploy();
    const keystone = await viem.deployContract("MockKeystoneForwarder");
    // Intentionally do not whitelist keystone.

    await viem.assertions.revertWithCustomError(
      keystone.write.route([keeper.address, fakeCreMetadata(), "0x"]),
      keeper,
      "NotForwarder",
    );
    assert.equal(await oracle.read.updateCount(), 0n);
  });

  it("CRE path: canUpdate is true before first report when oracle is ready", async function () {
    const { keeper } = await deploy();
    assert.equal(await keeper.read.canUpdate(), true);
  });

  it("CRE path: onReport gas stays under typical CRE writeReport gasLimit (500k)", async function () {
    const { keeper, keystone } = await deployWithMockKeystone();
    const gas = await publicClient.estimateContractGas({
      address: keystone.address,
      abi: keystone.abi,
      functionName: "route",
      args: [keeper.address, fakeCreMetadata(), "0x"],
      account: owner,
    });
    assert.ok(gas < 500_000n, `expected gas < 500000, got ${gas}`);
  });
});
