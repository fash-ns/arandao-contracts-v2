const orders = [
    {
      "orderBlockchainId": 159,
      "businessValue": "365000000000000000000",
      "sellerValue": "250000000000000000000",
      "contractAddress": "0xa131dc15f221cf99fa366f2E4E8A2424939a94D0",
      "blockchainUserId": 5263,
      "userWalletAddress": "0x3bA618890a6d57faEAD19Be322b3784dae6D283F",
      "blockchainSellerId": 1,
      "sellerWalletAddress": "0x6Bd6a164Bc92632946C33346F0E20B083bcbEfD5"
    },
    {
      "orderBlockchainId": 160,
      "businessValue": "15000000000000000000",
      "sellerValue": "65000000000000000000",
      "contractAddress": "0x6CE5ce6D69620AC43805bc6a84867daEC23E0c9B",
      "blockchainUserId": 5262,
      "userWalletAddress": "0x13538287bd511E76f9da838a979Bc23b877D88ad",
      "blockchainSellerId": 9,
      "sellerWalletAddress": "0xBe62116644149005A3e85376ca7399fBFb45Db87"
    },
    {
      "orderBlockchainId": 161,
      "businessValue": "365000000000000000000",
      "sellerValue": "250000000000000000000",
      "contractAddress": "0xa131dc15f221cf99fa366f2E4E8A2424939a94D0",
      "blockchainUserId": 5264,
      "userWalletAddress": "0x5C1d877914c38CF49477CE338405DAdEc8791a09",
      "blockchainSellerId": 1,
      "sellerWalletAddress": "0x6Bd6a164Bc92632946C33346F0E20B083bcbEfD5"
    },
    {
      "orderBlockchainId": 162,
      "businessValue": "3000000000000000000",
      "sellerValue": "12000000000000000000",
      "contractAddress": "0x6CE5ce6D69620AC43805bc6a84867daEC23E0c9B",
      "blockchainUserId": 5262,
      "userWalletAddress": "0x13538287bd511E76f9da838a979Bc23b877D88ad",
      "blockchainSellerId": 9,
      "sellerWalletAddress": "0xBe62116644149005A3e85376ca7399fBFb45Db87"
    },
    {
      "orderBlockchainId": 163,
      "businessValue": "100000000000000000000",
      "sellerValue": "1000000000000000000",
      "contractAddress": "0x6CE5ce6D69620AC43805bc6a84867daEC23E0c9B",
      "blockchainUserId": 5265,
      "userWalletAddress": "0x52E6AB66364005A6eFdd2E906a7B239D1F5058f8",
      "blockchainSellerId": 4,
      "sellerWalletAddress": "0x9F6aef6D10FCBb19B3918e3C76af9Dc600eE56Cd"
    },
    {
      "orderBlockchainId": 164,
      "businessValue": "4000000000000000000",
      "sellerValue": "20000000000000000000",
      "contractAddress": "0x6CE5ce6D69620AC43805bc6a84867daEC23E0c9B",
      "blockchainUserId": 5262,
      "userWalletAddress": "0x13538287bd511E76f9da838a979Bc23b877D88ad",
      "blockchainSellerId": 9,
      "sellerWalletAddress": "0xBe62116644149005A3e85376ca7399fBFb45Db87"
    },
    {
      "orderBlockchainId": 165,
      "businessValue": "100000000000000000000",
      "sellerValue": "1000000000000000000",
      "contractAddress": "0x6CE5ce6D69620AC43805bc6a84867daEC23E0c9B",
      "blockchainUserId": 5266,
      "userWalletAddress": "0x2bec504Dd9A1E31a7a7A6d00fDF9F34B103c1386",
      "blockchainSellerId": 9,
      "sellerWalletAddress": "0xBe62116644149005A3e85376ca7399fBFb45Db87"
    },
    {
      "orderBlockchainId": 166,
      "businessValue": "3000000000000000000",
      "sellerValue": "4000000000000000000",
      "contractAddress": "0x6CE5ce6D69620AC43805bc6a84867daEC23E0c9B",
      "blockchainUserId": 5243,
      "userWalletAddress": "0xb70FCD9D066D936b02B429fD68E5101D94ed41cc",
      "blockchainSellerId": 10,
      "sellerWalletAddress": "0x5778495244E59b81a1f69153e0d3355212a3751C"
    },
    {
      "orderBlockchainId": 167,
      "businessValue": "100000000000000000000",
      "sellerValue": "1000000000000000000",
      "contractAddress": "0x6CE5ce6D69620AC43805bc6a84867daEC23E0c9B",
      "blockchainUserId": 5267,
      "userWalletAddress": "0x8100a44628d134531E8a2e9aE5a34c39ea3cFefB",
      "blockchainSellerId": 4,
      "sellerWalletAddress": "0x9F6aef6D10FCBb19B3918e3C76af9Dc600eE56Cd"
    },
    {
      "orderBlockchainId": 168,
      "businessValue": "5500000000000000000",
      "sellerValue": "9000000000000000000",
      "contractAddress": "0x6CE5ce6D69620AC43805bc6a84867daEC23E0c9B",
      "blockchainUserId": 5267,
      "userWalletAddress": "0x8100a44628d134531E8a2e9aE5a34c39ea3cFefB",
      "blockchainSellerId": 10,
      "sellerWalletAddress": "0x5778495244E59b81a1f69153e0d3355212a3751C"
    }
  ]


  const totalBvAmount = orders.reduce((acc, order) => acc + parseInt((BigInt(order.businessValue) / BigInt("1000000000000000000")).toString()), 0);

  const sellers: Record<number, {address: string, bv: bigint}> = {};
  const users: Record<number, {address: string, bv: bigint}> = {};

  for (const order of orders) {
    if (!sellers[order.blockchainSellerId]) {
      sellers[order.blockchainSellerId] = {
        address: order.sellerWalletAddress,
        bv: BigInt(order.businessValue),
      };
    } else {
      sellers[order.blockchainSellerId].bv += BigInt(order.businessValue);
    }

    if (!users[order.blockchainUserId]) {
      users[order.blockchainUserId] = {
        address: order.userWalletAddress,
        bv: BigInt(order.businessValue),
      };
    } else {
      users[order.blockchainUserId].bv += BigInt(order.businessValue);
    }
  }

  console.log({sellers, users, totalBvAmount});