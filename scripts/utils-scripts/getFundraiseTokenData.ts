import tokenHolders from "../../deploy-utils/fundraiseTokenData.json";
import * as fs from "fs";

const users: Record<string, {tokenIds: number[], shares: number[]}> = {};

tokenHolders.forEach(item => {
    if (users[item.walletAddress]) {
        users[item.walletAddress].shares.push(item.editions);
        users[item.walletAddress].tokenIds.push(item.blockchainTokenId);
    } else {
        users[item.walletAddress] = {
            tokenIds: [item.blockchainTokenId],
            shares: [item.editions]
        }
    }
})

const finalData = [];

Object.entries(users).forEach(([key, val]) => {
    finalData.push({
        wallerAddress: key,
        tokenIds: val.tokenIds,
        editions: val.shares
    })
})

console.log(finalData.length);

fs.writeFileSync("./adaptedFundraiseShares.json", JSON.stringify(finalData, null, 2));