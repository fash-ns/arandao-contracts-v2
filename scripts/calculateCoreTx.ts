import jsonData from "../personal/coreTxs.json";
import readline from "readline";

const rl = readline.createInterface({
  input: process.stdin,
  output: process.stdout,
});
const pressAKey = async () => {
  return new Promise<void>((resolve) => {
    rl.question("Press enter to continue", (name) => {
      resolve();
    });
  });
};

const main = async () => {
  let balance = 0;
  const descJsonData = jsonData.reverse();
  for (const record of descJsonData) {
    const amount = parseFloat(record.Amount.toString().replace(",", ""));
    if (amount === 0) continue;
    if (record.Token !== "(PoS) Dai Stablecoin(DAI)") continue;
    if (record.From === "0x282b01760c0300e73a88d5466d6dddac16fb7c77") {
      console.log(`-${amount} -> ${record.To}`);
      balance -= amount as number;
    } else {
      console.log(`${amount} -> ${record.From}`);
      balance += amount as number;
    }
    console.log(`Core balance is now ${balance}`);
    await pressAKey();
  }
};

main();
