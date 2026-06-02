import { expect } from "chai";
import hre from "hardhat";
import { SnapshotRestorer } from "@nomicfoundation/hardhat-network-helpers/types";
import { createMarketTestHelpers } from "../../test-helpers/market-helpers.js";
import { parseEther, zeroAddress } from "viem";

const { ethers, networkHelpers } = await hre.network.create();
const signers = await ethers.getSigners();
const { deployContracts, mintArcForSigner, mockCreateProduct } =
  createMarketTestHelpers(ethers, signers);

describe("Market and MarketToken", () => {
  let snapshot: SnapshotRestorer;
  let contracts: Awaited<ReturnType<typeof deployContracts>>;

  before(async () => {
    contracts = await deployContracts();
    await contracts.core.addWhiteListContract(contracts.marketAddress);
    await contracts.core.setAddresses(
      contracts.twapAddress,
      contracts.yieldPoolAddress,
      contracts.fvAddress,
    );
    snapshot = await networkHelpers.takeSnapshot();
  });

  beforeEach(async () => {
    await snapshot.restore();
  });

  it("Only deployer can set mint operator for marketToken", async () => {
    const { marketAddress, marketToken } = contracts;

    await expect(
      marketToken.connect(signers[1]).setMintOperator(marketAddress),
    ).to.be.revertedWith("Only deployer can call");

    await marketToken.setMintOperator(marketAddress);
    expect(await marketToken.mintOperator()).to.equal(marketAddress);
  });

  it("Only deployer can revoke deployer", async () => {
    const { marketToken } = contracts;

    await expect(
      marketToken.connect(signers[1]).revokeDeployer(),
    ).to.be.revertedWith("Only deployer can call");

    await marketToken.revokeDeployer();
    expect(await marketToken.deployer()).to.equal(zeroAddress);
  });

  it("Deployer cannot set mint operator after revoke", async () => {
    const { marketAddress, marketToken } = contracts;

    await marketToken.revokeDeployer();

    await expect(marketToken.setMintOperator(marketAddress)).to.be.revertedWith(
      "Only deployer can call",
    );
  });

  it("Only mint operator can mint", async () => {
    const { marketToken } = contracts;

    await expect(
      marketToken.mint(
        "0x0000000000000000000000000000000000000001",
        2,
        "sampleIpfsCid",
      ),
    ).to.be.revertedWith("Only mint operator can mint");
    await expect(
      marketToken
        .connect(signers[1])
        .mint("0x0000000000000000000000000000000000000001", 2, "sampleIpfsCid"),
    ).to.be.revertedWith("Only mint operator can mint");

    await marketToken.setMintOperator(signers[1]);

    await expect(
      marketToken
        .connect(signers[1])
        .mint("0x0000000000000000000000000000000000000001", 2, "sampleIpfsCid"),
    ).to.emit(marketToken, "TransferSingle");
    expect(
      await marketToken.balanceOf(
        "0x0000000000000000000000000000000000000001",
        1,
      ),
    ).to.equal(2);
    expect(await marketToken.uri(1)).to.equal("sampleIpfsCid");
  });

  it("Seller cannot lock ARC if there's not any", async () => {
    const { market } = contracts;

    await expect(market.lockSellerArc()).to.be.revertedWith(
      "Seller has less ARC balance than required.",
    );
  });

  it("Seller cannot lock ARC without approve", async () => {
    const { market, arc, core } = contracts;
    await mintArcForSigner(core, arc, parseEther("1"), signers[1].address);

    await expect(
      market.connect(signers[1]).lockSellerArc(),
    ).to.be.revertedWithCustomError(arc, "ERC20InsufficientAllowance");
  });

  it("Seller can lock ARC", async () => {
    const { market, arc, core, marketAddress } = contracts;
    await mintArcForSigner(core, arc, parseEther("1"), signers[1].address);

    await arc.connect(signers[1]).approve(marketAddress, parseEther("1"));

    await expect(market.connect(signers[1]).lockSellerArc()).to.emit(
      market,
      "SellerLockedArc",
    );
    expect(await arc.balanceOf(signers[1].address)).to.equal(0);
    expect(await arc.balanceOf(marketAddress)).to.equal(parseEther("1"));
  });

  it("Seller cannot withdraw ARC before a year", async () => {
    const { market, arc, core, marketAddress } = contracts;
    await mintArcForSigner(core, arc, parseEther("1"), signers[1].address);

    await arc.connect(signers[1]).approve(marketAddress, parseEther("1"));

    await market.connect(signers[1]).lockSellerArc();

    await networkHelpers.time.increase(180 * 86400);

    await expect(
      market.connect(signers[1]).withdrawSellerArc(),
    ).to.be.revertedWith("Seller ARC must be locked for at least 1 year.");

    await networkHelpers.time.increase(185 * 86400);

    await expect(market.connect(signers[1]).withdrawSellerArc()).to.emit(
      market,
      "SellerWithdrawnArc",
    );
    expect(await arc.balanceOf(signers[1].address)).to.equal(parseEther("1"));
    expect(await arc.balanceOf(marketAddress)).to.equal(0);
  });

  it("Seller cannot withdraw ARC if it's not locked", async () => {
    const { market } = contracts;
    await expect(
      market.connect(signers[1]).withdrawSellerArc(),
    ).to.be.revertedWith("Seller ARC is not locked");
  });

  it("Seller cannot create product if ARC not locked", async () => {
    const { market } = contracts;

    await expect(
      market.createProduct(100 * 1e6, 50 * 1e6, 10, "sampleProduct"),
    ).to.be.revertedWith("User has not locked ARC yet");
  });

  it("Seller cannot create product with SV less than 1% of BV", async () => {
    const { market, marketToken, arc, core, marketAddress } = contracts;
    await marketToken.setMintOperator(marketAddress);
    await mintArcForSigner(core, arc, parseEther("1"), signers[0].address);

    await arc.approve(marketAddress, parseEther("1"));

    await market.lockSellerArc();

    await expect(
      market.createProduct(1000 * 1e6, 1 * 1e6, 10, "sampleProduct"),
    ).to.be.revertedWith("SV Should be greater than 1 percent of BV.");
  });

  it("Seller can create product", async () => {
    const { market, marketToken, arc, core, marketAddress } = contracts;
    await marketToken.setMintOperator(marketAddress);
    await mintArcForSigner(core, arc, parseEther("1"), signers[0].address);

    await arc.approve(marketAddress, parseEther("1"));

    await market.lockSellerArc();

    await expect(
      market.createProduct(1000 * 1e6, 10 * 1e6, 10, "sampleProduct"),
    ).to.emit(market, "ProductCreated");
  });

  it("Seller cannot set product status if it doesn't exist", async () => {
    const { market } = contracts;

    await expect(market.setProductStatus(1, true)).to.be.revertedWith(
      "Product not found",
    );
  });

  it("Seller cannot set product status for someone else", async () => {
    const { market, marketToken, core, arc, marketAddress } = contracts;
    await mintArcForSigner(core, arc, parseEther("1"), signers[1].address);
    await arc.connect(signers[1]).approve(marketAddress, parseEther("1"));
    await market.connect(signers[1]).lockSellerArc();
    await mockCreateProduct(market, marketToken, signers[1]);

    await expect(market.setProductStatus(1, true)).to.be.revertedWith(
      "Only seller can toggle product status",
    );
  });

  it("Seller can set product status his products", async () => {
    const { market, marketToken, core, arc, marketAddress } = contracts;
    await mintArcForSigner(core, arc, parseEther("1"), signers[1].address);
    await arc.connect(signers[1]).approve(marketAddress, parseEther("1"));
    await market.connect(signers[1]).lockSellerArc();
    await mockCreateProduct(market, marketToken, signers[1]);

    expect((await market.products(1)).active).to.be.true;
    await expect(market.connect(signers[1]).setProductStatus(1, false)).to.emit(
      market,
      "ProductStatusChanged",
    );
    expect((await market.products(1)).active).to.be.false;
  });

  it("Buyer cannot purchase not existed product", async () => {
    const { market } = contracts;
    await expect(
      market.purchaseProduct(
        [
          {
            productId: 1,
            quantity: 2,
          },
        ],
        zeroAddress,
        0,
      ),
    ).to.be.revertedWith("Product not found");
  });

  it("Buyer cannot purchase more quantity than available", async () => {
    const { market, marketToken, core, arc, marketAddress } = contracts;
    await mintArcForSigner(core, arc, parseEther("1"), signers[1].address);
    await arc.connect(signers[1]).approve(marketAddress, parseEther("1"));
    await market.connect(signers[1]).lockSellerArc();
    await mockCreateProduct(market, marketToken, signers[1]);

    await expect(
      market.purchaseProduct(
        [
          {
            productId: 1,
            quantity: 20,
          },
        ],
        zeroAddress,
        0,
      ),
    ).to.be.revertedWithCustomError(market, "MarketSellerInsufficientBalance");
  });

  it("Buyer cannot purchase own product", async () => {
    const { market, marketToken, core, arc, marketAddress } = contracts;
    await mintArcForSigner(core, arc, parseEther("1"), signers[1].address);
    await arc.connect(signers[1]).approve(marketAddress, parseEther("1"));
    await market.connect(signers[1]).lockSellerArc();
    await mockCreateProduct(market, marketToken, signers[1]);

    await expect(
      market.connect(signers[1]).purchaseProduct(
        [
          {
            productId: 1,
            quantity: 5,
          },
        ],
        zeroAddress,
        0,
      ),
    ).to.be.revertedWith("User cannot purchase his own product.");
  });

  it("Buyer cannot purchase without USDT balance", async () => {
    const { market, marketToken, core, arc, marketAddress } = contracts;
    await mintArcForSigner(core, arc, parseEther("1"), signers[1].address);
    await arc.connect(signers[1]).approve(marketAddress, parseEther("1"));
    await market.connect(signers[1]).lockSellerArc();
    await mockCreateProduct(market, marketToken, signers[1]);

    await expect(
      market.connect(signers[2]).purchaseProduct(
        [
          {
            productId: 1,
            quantity: 5,
          },
        ],
        zeroAddress,
        0,
      ),
    ).to.be.revertedWithCustomError(market, "MarketBuyerInsufficientBalance");
  });

  it("Buyer cannot purchase without USDT alowance", async () => {
    const { market, marketToken, core, arc, usdt, marketAddress } = contracts;
    await mintArcForSigner(core, arc, parseEther("1"), signers[1].address);
    await arc.connect(signers[1]).approve(marketAddress, parseEther("1"));
    await market.connect(signers[1]).lockSellerArc();
    await mockCreateProduct(market, marketToken, signers[1]);

    await expect(
      market.purchaseProduct(
        [
          {
            productId: 1,
            quantity: 5,
          },
        ],
        zeroAddress,
        0,
      ),
    ).to.be.revertedWithCustomError(usdt, "ERC20InsufficientAllowance");
  });

  it("Buyer can purchase an existed product", async () => {
    const {
      market,
      marketToken,
      core,
      arc,
      usdt,
      marketAddress,
      coreAddress,
      fvAddress,
    } = contracts;
    await mintArcForSigner(core, arc, parseEther("1"), signers[1].address);
    await arc.connect(signers[1]).approve(marketAddress, parseEther("1"));
    await market.connect(signers[1]).lockSellerArc();
    await mockCreateProduct(market, marketToken, signers[1]);

    const buyerBalanceBefore = await usdt.balanceOf(signers[0].address);

    await usdt.approve(marketAddress, 302 * 1e6);

    await expect(
      market.purchaseProduct(
        [
          {
            productId: 1,
            quantity: 2,
          },
        ],
        zeroAddress,
        0,
      ),
    ).to.emit(core, "OrderCreated");

    const buyerBalanceAfter = await usdt.balanceOf(signers[0].address);

    expect(buyerBalanceBefore - buyerBalanceAfter).to.equal(302 * 1e6);
    expect(
      await usdt.balanceOf("0x0000000000000000000000000000000000000010"),
    ).to.equal(4 * 1e6);
    expect(await usdt.balanceOf(signers[1].address)).to.equal(98 * 1e6);
    expect(await usdt.balanceOf(coreAddress)).to.equal(160 * 1e6);
    expect(await usdt.balanceOf(fvAddress)).to.equal(40 * 1e6);
    expect(await marketToken.balanceOf(signers[0].address, 1)).to.equal(2);
    expect(await marketToken.balanceOf(signers[1].address, 1)).to.equal(8);
  });
});
