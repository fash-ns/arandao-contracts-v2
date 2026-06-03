import hre from "hardhat";

const { ethers, networkHelpers } = await hre.network.create();

const signers = await ethers.getSigners();

// await signers[1].sendTransaction({
//     to: signers[0].address,
//     value: ethers.parseEther("5000")
// })

const balance = await ethers.provider.getBalance(signers[0].address);
console.log(balance);
