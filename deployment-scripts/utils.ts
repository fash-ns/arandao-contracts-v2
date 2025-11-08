import { ethers, type InterfaceAbi } from "ethers";

export const parseError = (abi: InterfaceAbi, error: string) => {
    const iface = new ethers.Interface(abi);
    const parsedError = iface.parseError(error);
    console.log(parsedError)
    return parsedError;
}