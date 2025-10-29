import dotenv from "dotenv";
dotenv.config({
  path: ".env.local",
});

import type { HardhatUserConfig } from "hardhat/config";
import hardhatVerify from "@nomicfoundation/hardhat-verify";

import hardhatToolboxViemPlugin from "@nomicfoundation/hardhat-toolbox-viem";
import { configVariable } from "hardhat/config";

const config: HardhatUserConfig = {
  plugins: [hardhatToolboxViemPlugin, hardhatVerify],
  verify: {
    etherscan: {
      apiKey: '5EM6UZUS3XWKCSMEFP1M528WGP6HY6UY9U', //configVariable("ETHERSCAN_API_KEY"),
    },
  },
  chainDescriptors: {
    // Example chain
    11155111: {
      name: "etherscan",
      blockExplorers: {
        etherscan: {
          name: "etherscan",
          url: "https://api-sepolia.etherscan.io",
          apiUrl: "https://api-sepolia.etherscan.io/api",
        },
      },
    },
  },
  solidity: {
    profiles: {
      default: {
        version: "0.8.28",
        settings: {
          optimizer: {
            enabled: true,
            runs: 200,
          },
        },
      },
      production: {
        version: "0.8.28",
        settings: {
          optimizer: {
            enabled: true,
            runs: 200,
          },
        },
      },
    },
  },
  networks: {
    hardhatMainnet: {
      type: "edr-simulated",
      chainType: "l1",
    },
    hardhatOp: {
      type: "edr-simulated",
      chainType: "op",
    },
    localhost: {
      type: "http",
      chainType: "l1",
      url: "http://127.0.0.1:8545",
      accounts: [configVariable("LOCALHOST_PRIVATE_KEY")],
    },
    sepolia: {
      type: "http",
      chainType: "l1",
      url: configVariable("SEPOLIA_RPC_URL"),
      accounts: [configVariable("SEPOLIA_PRIVATE_KEY")],
    },
    amoy: {
      type: "http",
      chainType: "op",
      url: configVariable("AMOY_RPC_URL"),
      accounts: [configVariable("AMOY_PRIVATE_KEY")],
    },
  },
};

export default config;
