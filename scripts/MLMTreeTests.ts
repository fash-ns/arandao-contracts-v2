import { network } from "hardhat";
import { decodeErrorResult } from "viem";
import { generatePrivateKey, privateKeyToAccount, privateKeyToAddress } from "viem/accounts";

const {viem} = await network.connect({
    network: 'hardhatMainnet',
    chainType: "l1",
});

const mlmTree = await viem.deployContract("MLMTree");

try {
    await mlmTree.write.registerUser([`0xf39fd6e51aad88f6f4c00000027279cfffb92266`, 0, 0]);
    for (let i = 1; i <= 33; i++) {
        const pk = generatePrivateKey();
        const address = privateKeyToAddress(pk);
        const pos = Math.floor(Math.random() * 4);
        await mlmTree.write.registerUser([address, i, pos]);
    }
    const res = await mlmTree.read.getUserPath([34]);
    // const res = await mlmTree.read.isSubTree([2, 8]);
    console.log(res);
} catch (error: any) {
    console.log(error);
    // console.log(decodeErrorResult(error));
}

console.log("OK")