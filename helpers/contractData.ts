import arcAbi from "../artifacts/contracts/arc/ARC.sol/AssetRightsCoin.json";
import twapAbi from "../artifacts/contracts/oracle/TwapOracle.sol/TwapOracle.json";
import coreAbi from "../artifacts/contracts/core/Core.sol/DNMCore.json";
import fvAbi from "../artifacts/contracts/fastValue/FastValue.sol/FastValue.json";
import yieldPoolAbi from "../artifacts/contracts/yieldPool/YieldPool.sol/YieldPool.json";
import marketTokenAbi from "../artifacts/contracts/market/MarketToken.sol/DNMMintedProduct.json";
import marketAbi from "../artifacts/contracts/market/Market.sol/DMarket.json";
import dexAbi from "../artifacts/contracts/dex/Dex.sol/Dex.json";
import fundraiseCollectionAbi from "../artifacts/contracts/collection/Collection.sol/NftFundRaiseCollection.json";
import fundraiseOrderBookAbi from "../artifacts/contracts/orderBook/OrderBook.sol/NFTFundRaiseOrderBook.json";

import { InterfaceAbi } from "ethers";

const contractData: Record<string, { address: string; abi: InterfaceAbi }> = {
  usdt: {
    address: "0xdac17f958d2ee523a2206206994597c13d831ec7",
    abi: arcAbi.abi,
  },
  arc: {
    address: "0x4bCB20F928E446cBD05ddD28576299399D82580E",
    abi: arcAbi.abi,
  },
  twap: {
    address: "0xD79Ff8D88B6150A86c8395D9a65dB795266d7521",
    abi: twapAbi.abi,
  },
  core: {
    address: "0x4cCFbF5DDa901876Ca4415E7cbcBE70349BD216F",
    abi: coreAbi.abi,
  },
  fastValue: {
    address: "0x868a18BeB99Bcf800265e3BD734B5fb356229f9B",
    abi: fvAbi.abi,
  },
  yieldPool: {
    address: "0xDdA135A0d36455d96A873F174a415b55e2d04157",
    abi: yieldPoolAbi.abi,
  },
  mintedProduct: {
    address: "0xd4d7c4258b0d93B2375599Aff3F502C181b9bc2E",
    abi: marketTokenAbi.abi,
  },
  market: {
    address: "0x2d8D4272b0a7EB921d93aA846859d2fe14A8A116",
    abi: marketAbi.abi,
  },
  dex: {
    address: "0xAb7dF55a24d866bC8BFFa77b78032D6f0b2AF00A",
    abi: dexAbi.abi,
  },
  fundraiseCollection: {
    address: "0xef18157c255dCa18D07117AAed4Ea828787Ce7D1",
    abi: fundraiseCollectionAbi.abi,
  },
  fundraiseOrderBook: {
    address: "0x73566A4C4dA22bacC15b7ed282bAE8FD7597F136",
    abi: fundraiseOrderBookAbi.abi,
  },
};

export const getContractData = (
  contract: string,
): { address: string; abi: InterfaceAbi } => {
  if (contractData.hasOwnProperty(contract)) return contractData[contract];
  else throw new Error("Contract not found");
};