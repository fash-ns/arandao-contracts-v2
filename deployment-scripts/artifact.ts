import hre from "hardhat";

const { ethers } = await hre.network.connect();

const artifact = async () => {
    const local = await hre.artifacts.readArtifact("AssetRightsCoin");
const deployed = await ethers.provider.getCode("0x7415EA930e56d7A098cbD78600DE51f575c8ab60");
console.log(local.deployedBytecode === deployed); // should be true
console.log({deployed: deployed, local: local.deployedBytecode});
}

artifact();