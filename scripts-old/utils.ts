import { ethers, type InterfaceAbi } from "ethers";

export const parseError = (abi: InterfaceAbi, error: string) => {
  const iface = new ethers.Interface(abi);
  const parsedError = iface.parseError(error);
  console.log(parsedError);
  return parsedError;
};

const test = () => {
  const pastWeekTotalBv = BigInt("3260000000000000000000");
  const priceFromVault = BigInt("1000000000000000000");
  const totalSupply = BigInt("1100000000000000000000");
  const adjustedSupply = BigInt("1100000000000000000000");

  const p =
    (((pastWeekTotalBv * BigInt("397")) / BigInt("1000") +
      (priceFromVault * totalSupply) / BigInt("1000000000000000000")) *
      BigInt("1000000000000000000")) /
    adjustedSupply;

  const mintAmount =
    (((pastWeekTotalBv * BigInt("78")) / BigInt("1000")) *
      BigInt("1000000000000000000")) /
    p;
  console.log(mintAmount);
};
