module.exports = [
  "0xCdA1cf578049c46e7A007A0b00e4F5F2fbe419a5", // initialOwner
  "0x569D5b74557F8923bBefde4c249CAE55Fab181A5", // dnmToken
  "0xab23d706A06a8dF824C6b8433B652753e8E07A91", // daiToken
  "0xf5D0855De893Abda892DA296c3d3E847CC926AcD", // feeReceiver
  "0x3E62eD1984910D1f7A5CD2E670c53D1aF0F6F96d", // vault
  [{
    volumeFloor: 0n,
    feeBps: 10n
  }, {
    volumeFloor: 10000000000000000000n,
    feeBps: 20n
  }, {
    volumeFloor: 100000000000000000000n,
    feeBps: 30n
  }, {
    volumeFloor: 500000000000000000000n,
    feeBps: 40n
  }, {
    volumeFloor: 1000000000000000000000n,
    feeBps: 100n
  }],                                           // Fees
]