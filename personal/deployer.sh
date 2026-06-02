#!/bin/bash

NETWORK=localhost

npx hardhat ignition deploy --network localhost ./ignition/modules/mock/Aa.Asc.ts

npx hardhat ignition deploy --network $NETWORK ./ignition/modules/Aa.Arc.ts
npx hardhat ignition deploy --network $NETWORK ./ignition/modules/Ab.Twap.ts
npx hardhat ignition deploy --network $NETWORK ./ignition/modules/Ac.Core.ts
npx hardhat ignition deploy --network $NETWORK ./ignition/modules/Ad.FastValue.ts
npx hardhat ignition deploy --network $NETWORK ./ignition/modules/Ae.YieldPool.ts
npx hardhat ignition deploy --network $NETWORK ./ignition/modules/Af.MarketToken.ts 
npx hardhat ignition deploy --network $NETWORK ./ignition/modules/Ag.Market.ts
npx hardhat ignition deploy --network $NETWORK ./ignition/modules/Ah.Dex.ts
npx hardhat ignition deploy --network $NETWORK ./ignition/modules/Ai.FundraiseCollection.ts
npx hardhat ignition deploy --network $NETWORK ./ignition/modules/Aj.FundraiseOrderBook.ts