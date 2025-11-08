import arcAbi from "../artifacts/contracts/dnm/ARC.sol/AssetRightsCoin.json";
import bridgeAbi from "../artifacts/contracts/bridge/Bridge.sol/AranDAOBridge.json";
import priceFeedAbi from "../artifacts/contracts/vault/VaultCore/PriceFeed.sol/PriceFeed.json";
import vaultAbi from "../artifacts/contracts/vault/Vault.sol/MultiAssetVault.json";
import coreAbi from "../artifacts/contracts/core/Core.sol/DNMCore.json";
import mintedProductAbi from "../artifacts/contracts/market/MarketToken.sol/DNMMintedProduct.json";
import marketAbi from "../artifacts/contracts/market/Market.sol/DMarket.json";
import dexAbi from "../artifacts/contracts/dex/Dex.sol/Dex.json";
import fundraiseTokenAbi from "../artifacts/contracts/collection/Collection.sol/NftFundRaiseCollection.json";
import fundraiseMarketAbi from "../artifacts/contracts/orderBook/OrderBook.sol/NFTFundRaiseOrderBook.json";

import dnmAbi from "../artifacts/contracts/mock/old-contracts/DNM.sol/DNM.json";
import uvmAbi from "../artifacts/contracts/mock/old-contracts/UVM.sol/UVM.json";
import wrapperAbi from "../artifacts/contracts/mock/old-contracts/Wrapper.sol/Wrapper.json";
import stakeAbi from "../artifacts/contracts/mock/old-contracts/StakeMeta.sol/StakeMeta.json";
import { InterfaceAbi } from "ethers";

const contractData: Record<string, {address: string, abi: InterfaceAbi}> = {
    arc: {
        address: "0xCb7FE699e4b513d863ce16628638c496C6eE006f",
        abi: arcAbi.abi
    },
    bridge: {
        address: "0x8b465E932b9c20a6e780E4898eDcC67E6B79D9B3",
        abi: bridgeAbi.abi
    },
    priceFeed: {
        address: "0x3E57904F3406E01B5a7854F6Bb670A6359B0872d",
        abi: priceFeedAbi.abi
    },
    core: {
        address: "0xffC9Ff6f279e0AbF1b00DEE755bd74d81315e0cc",
        abi: coreAbi.abi
    },
    vault: {
        address: "0x8E267f42e52CB3C322d2Db90B15eFF754998E474",
        abi: vaultAbi.abi
    },
    mintedProduct: {
        address: "0xa11d4F5a56a7f8ad2a057d40841567A9FC08d3fD",
        abi: mintedProductAbi.abi
    },
    market: {
        address: "0x488779130628f9f47B5A12B41F41C22672d6F5E7",
        abi: marketAbi.abi
    },
    // dex: {
    //     address: "0xb43c541Fb96EFdeb7c9B3D35B9Db3A8458F2f91c",
    //     abi: dexAbi.abi
    // },
    fundraiseToken: {
        address: "0xDeECf5C91CcF21C1B2E07De811A9bc85Ba77A8e7",
        abi: fundraiseTokenAbi.abi
    },
    fundraiseMarket: {
        address: "0x110E28Fc17dB9dF562160E322D90E8300d99133E",
        abi: fundraiseMarketAbi.abi
    },

    dnm: {
        address: "0x76d80320d09fed78b1eb49d304345901a44485c0",
        abi: dnmAbi.abi
    },
    uvm: {
        address: "0x6966feC28Ae7F598Bd29C788deF80f56FFa12dE9",
        abi: uvmAbi.abi
    },
    wrapper: {
        address: "0xfcBeF011C9716Bf922F055F65e217A3b8713Cf43",
        abi: wrapperAbi.abi
    },
    stake: {
        address: "0x873DF99ac751a6A2F7607379a83B7b26178736FD",
        abi: stakeAbi.abi
    },
    dai: {
        address: "0x8f3Cf7ad23Cd3CaDbD9735AFf958023239c6A063",
        abi: uvmAbi.abi
    },
}

export const getContractData = (contract: string): {address: string, abi: InterfaceAbi} => {
    if (contractData.hasOwnProperty(contract))
        return contractData[contract]
    else throw new Error("Contract not found");
}