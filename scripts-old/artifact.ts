import { network, artifacts } from "hardhat";
import { getContractData } from "../helpers/contractData.js";
import { parseError } from "./utils.js";

const { ethers } = await network.connect();

const artifact = async () => {
  const local = await artifacts.readArtifact("AssetRightsCoin");
  const deployed = await ethers.provider.getCode(
    "0x7415EA930e56d7A098cbD78600DE51f575c8ab60",
  );
  console.log(local.deployedBytecode === deployed); // should be true
  console.log({ deployed: deployed, local: local.deployedBytecode });
};

const readError = async () => {
  const contractData = getContractData("market");
  const errorLog = parseError(
    contractData.abi,
    "0x0000000000000000000000000000000000000000000000000006ba7e21718f80000000000000000000000000000000000000000000000000c1d05966121cfec60000000000000000000000000000000000000000000226a4bcd42f30978e7718000000000000000000000000000000000000000000000000c1c99ee7f0ab6f460000000000000000000000000000000000000000000226a4bcdae9aeb9000698",
  );
  console.log(errorLog);
};

// artifact();
readError();
