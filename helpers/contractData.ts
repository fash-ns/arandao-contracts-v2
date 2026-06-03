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
    address: "0x75080099BBbdE4af79fa08407742D4CD95ea02aA",
    abi: arcAbi.abi,
  },
  twap: {
    address: "0x89D9eA98d357151e411f299822fA49f66dC943b0",
    abi: twapAbi.abi,
  },
  core: {
    address: "0xF6B601A5D02701308613C234244A9a3327EeA2fa",
    abi: coreAbi.abi,
  },
  fastValue: {
    address: "0x0d474d346019a46DBfe7Aaa566B347C5D3fD12A6",
    abi: fvAbi.abi,
  },
  yieldPool: {
    address: "0x96785EFc98C1FBC6f5C4829fB34150BA41C69E8e",
    abi: yieldPoolAbi.abi,
  },
  mintedProduct: {
    address: "0xb9b147cc108D03871F7DaA3B15A697511a19F501",
    abi: marketTokenAbi.abi,
  },
  market: {
    address: "0xC0bf0267D3804C70320d3e66ECB73f30c062B734",
    abi: marketAbi.abi,
  },
  dex: {
    address: "0x4d427e1a7E79D842A5047BEA4B3559D071043757",
    abi: dexAbi.abi,
  },
  fundraiseCollection: {
    address: "0x03D963421D0A31838467bce5B034BC34Ab258CBe",
    abi: fundraiseCollectionAbi.abi,
  },
  fundraiseOrderBook: {
    address: "0xB1c65b74035f58c489D98577F64fA9bc565655E5",
    abi: fundraiseOrderBookAbi.abi,
  },
};

export const getContractData = (
  contract: string,
): { address: string; abi: InterfaceAbi } => {
  if (contractData.hasOwnProperty(contract)) return contractData[contract];
  else throw new Error("Contract not found");
};
