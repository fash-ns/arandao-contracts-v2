#!/bin/bash

NETWORK=localhost

yarn hardhat ignition deploy --network $NETWORK ./ignition/modules/Aa.Dnm.ts
yarn hardhat ignition deploy --network $NETWORK ./ignition/modules/Ab.Bridge.ts
yarn hardhat ignition deploy --network $NETWORK ./ignition/modules/Ac.PriceFeed.ts
yarn hardhat ignition deploy --network $NETWORK ./ignition/modules/Ad.Core.ts
yarn hardhat ignition deploy --network $NETWORK ./ignition/modules/Ae.Vault.ts
yarn hardhat ignition deploy --network $NETWORK ./ignition/modules/Af.MarketToken.ts 
yarn hardhat ignition deploy --network $NETWORK ./ignition/modules/Ag.Market.ts
# yarn hardhat ignition deploy --network $NETWORK ./ignition/modules/Ah.Dex.ts
yarn hardhat ignition deploy --network $NETWORK ./ignition/modules/Ai.FundraiseCollection.ts
yarn hardhat ignition deploy --network $NETWORK ./ignition/modules/Aj.NftFundRaise.ts