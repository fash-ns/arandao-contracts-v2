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
    address: "0x0A3EE490d067C266Ceb6f17aA43bBE7732Ed11c9",
    abi: arcAbi.abi,
  },
  arc: {
    address: "0x3AA3DCE3a62fd37Ce28C1120d34A970b371cB69E",
    abi: arcAbi.abi,
  },
  twap: {
    address: "0xe5e56701f7e241cc8C598615C4FBf6EF1ECf27B6",
    abi: twapAbi.abi,
  },
  core: {
    address: "0xe4621D0e194F6E6169e39B3eF1B300de9fBf5d95",
    abi: coreAbi.abi,
  },
  fastValue: {
    address: "0xeDa71b4Bcf8ccd0b6EccC021Bb3c8c2AD29bA21e",
    abi: fvAbi.abi,
  },
  yieldPool: {
    address: "0xb22e25FD4AC4E913384c02209b73b2fD256f511a",
    abi: yieldPoolAbi.abi,
  },
  mintedProduct: {
    address: "0x3ef9Fdc60762ca76a7f21562244745695172829D",
    abi: marketTokenAbi.abi,
  },
  market: {
    address: "0x53DAA94ADC9d43e3501Ef7F815F54a101e2c496F",
    abi: marketAbi.abi,
  },
  dex: {
    address: "0xB8fA00f68457E3234f22502A3a554Fe6A36ce259",
    abi: dexAbi.abi,
  },
  fundraiseCollection: {
    address: "0x5bf75299DbCadbEbCb6f0A9F9a1fE1C2B4bD9722",
    abi: fundraiseCollectionAbi.abi,
  },
  fundraiseOrderBook: {
    address: "0x0cA16890798d712100166412d2EAcfA1df7d5207",
    abi: fundraiseOrderBookAbi.abi,
  },
};

export const getContractData = (
  contract: string,
): { address: string; abi: InterfaceAbi } => {
  if (contractData.hasOwnProperty(contract)) return contractData[contract];
  else throw new Error("Contract not found");
};