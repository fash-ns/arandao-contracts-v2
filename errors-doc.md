# Contract Errors Documentation

Generated from ABI artifacts under `artifacts/contracts`.

Total unique contract/error entries: **95**

| Error Name | Contract Name | Description |
| --- | --- | --- |
| `ERC20InsufficientAllowance` | `AssetRightsCoin` | Indicates erc20 insufficient allowance. Params: spender: address, allowance: uint256, needed: uint256. |
| `ERC20InsufficientBalance` | `AssetRightsCoin` | Indicates erc20 insufficient balance. Params: sender: address, balance: uint256, needed: uint256. |
| `ERC20InvalidApprover` | `AssetRightsCoin` | Indicates erc20 invalid approver. Params: approver: address. |
| `ERC20InvalidReceiver` | `AssetRightsCoin` | Indicates erc20 invalid receiver. Params: receiver: address. |
| `ERC20InvalidSender` | `AssetRightsCoin` | Indicates erc20 invalid sender. Params: sender: address. |
| `ERC20InvalidSpender` | `AssetRightsCoin` | Indicates erc20 invalid spender. Params: spender: address. |
| `CannotFillOwnOrder` | `Dex` | Indicates cannot fill own order. |
| `FeeReceiverAlreadyChanged` | `Dex` | Indicates fee receiver already changed. |
| `InsufficientOrderAmount` | `Dex` | Indicates insufficient order amount. |
| `InvalidAmounts` | `Dex` | Indicates an invalid amounts value. |
| `OrderNotActive` | `Dex` | Indicates order not active. |
| `OrderNotFound` | `Dex` | Indicates order not found. |
| `ReentrancyGuardReentrantCall` | `Dex` | Indicates reentrancy guard reentrant call. |
| `SafeERC20FailedOperation` | `Dex` | Indicates safe erc20 failed operation. Params: token: address. |
| `SameTokens` | `Dex` | Indicates same tokens. |
| `Unauthorized` | `Dex` | Indicates an unauthorized caller or operation. |
| `ZeroAddress` | `Dex` | Indicates that a zero address was provided. |
| `MarketBuyerInsufficientBalance` | `DMarket` | Indicates market buyer insufficient balance. Params: requiredBalance: uint256, availableBalance: uint256. |
| `MarketProductInactive` | `DMarket` | Indicates market product inactive. Params: productId: uint256. |
| `MarketSellerArcNotLocked` | `DMarket` | Indicates market seller arc not locked. Params: sellerAddress: address. |
| `MarketSellerInsufficientBalance` | `DMarket` | Indicates market seller insufficient balance. Params: requiredBalance: uint256, availableBalance: uint256. |
| `SafeERC20FailedOperation` | `DMarket` | Indicates safe erc20 failed operation. Params: token: address. |
| `AddressAlreadyRegistered` | `DNMCore` | Indicates address already registered. |
| `FirstUserMustBeRoot` | `DNMCore` | Indicates first user must be root. |
| `InsufficientBVForNewUser` | `DNMCore` | Indicates insufficient bvfor new user. |
| `InvalidParentAddress` | `DNMCore` | Indicates an invalid parent address value. |
| `InvalidPosition` | `DNMCore` | Indicates an invalid position value. |
| `OrderNotExisted` | `DNMCore` | Indicates order not existed. Params: orderId: uint256. |
| `OwnableInvalidOwner` | `DNMCore` | Indicates ownable invalid owner. Params: owner: address. |
| `OwnableUnauthorizedAccount` | `DNMCore` | Indicates an unauthorized caller or operation. Params: account: address. |
| `ParentInsufficientBVForPosition` | `DNMCore` | Indicates parent insufficient bvfor position. Params: position: uint8, parentBv: uint256. |
| `PositionAlreadyTaken` | `DNMCore` | Indicates position already taken. |
| `ReentrancyGuardReentrantCall` | `DNMCore` | Indicates reentrancy guard reentrant call. |
| `SafeERC20FailedOperation` | `DNMCore` | Indicates safe erc20 failed operation. Params: token: address. |
| `SellerNotRegistered` | `DNMCore` | Indicates seller not registered. |
| `UnauthorizedAddress` | `DNMCore` | Indicates an unauthorized caller or operation. Params: _address: address. |
| `UnauthorizedContract` | `DNMCore` | Indicates an unauthorized caller or operation. Params: contractAddress: address. |
| `UserNotRegistered` | `DNMCore` | Indicates user not registered. |
| `UserNotRequestedChangeAddress` | `DNMCore` | Indicates user not requested change address. |
| `CannotWithdrawCurrentMonthShare` | `FastValue` | Indicates cannot withdraw current month share. |
| `NotInDevMode` | `FastValue` | Indicates the required condition 'in dev mode' is not met. |
| `OwnableInvalidOwner` | `FastValue` | Indicates ownable invalid owner. Params: owner: address. |
| `OwnableUnauthorizedAccount` | `FastValue` | Indicates an unauthorized caller or operation. Params: account: address. |
| `ReentrancyGuardReentrantCall` | `FastValue` | Indicates reentrancy guard reentrant call. |
| `SafeERC20FailedOperation` | `FastValue` | Indicates safe erc20 failed operation. Params: token: address. |
| `UnAuthorizedCoreContract` | `FastValue` | Indicates an unauthorized caller or operation. |
| `UnAuthorizedOwner` | `FastValue` | Indicates an unauthorized caller or operation. |
| `UserHasAlreadyWithdrawnFastValueShare` | `FastValue` | Indicates user has already withdrawn fast value share. |
| `UserHasNoFastValueShares` | `FastValue` | Indicates user has no fast value shares. |
| `UserNotFound` | `FastValue` | Indicates user not found. |
| `ERC1155InsufficientBalance` | `NftFundRaiseCollection` | Indicates erc1155 insufficient balance. Params: sender: address, balance: uint256, needed: uint256, tokenId: uint256. |
| `ERC1155InvalidApprover` | `NftFundRaiseCollection` | Indicates erc1155 invalid approver. Params: approver: address. |
| `ERC1155InvalidArrayLength` | `NftFundRaiseCollection` | Indicates erc1155 invalid array length. Params: idsLength: uint256, valuesLength: uint256. |
| `ERC1155InvalidOperator` | `NftFundRaiseCollection` | Indicates erc1155 invalid operator. Params: operator: address. |
| `ERC1155InvalidReceiver` | `NftFundRaiseCollection` | Indicates erc1155 invalid receiver. Params: receiver: address. |
| `ERC1155InvalidSender` | `NftFundRaiseCollection` | Indicates erc1155 invalid sender. Params: sender: address. |
| `ERC1155MissingApprovalForAll` | `NftFundRaiseCollection` | Indicates erc1155 missing approval for all. Params: operator: address, owner: address. |
| `OwnableInvalidOwner` | `NftFundRaiseCollection` | Indicates ownable invalid owner. Params: owner: address. |
| `OwnableUnauthorizedAccount` | `NftFundRaiseCollection` | Indicates an unauthorized caller or operation. Params: account: address. |
| `ReentrancyGuardReentrantCall` | `NftFundRaiseCollection` | Indicates reentrancy guard reentrant call. |
| `SafeERC20FailedOperation` | `NftFundRaiseCollection` | Indicates safe erc20 failed operation. Params: token: address. |
| `ReentrancyGuardReentrantCall` | `NFTFundRaiseOrderBook` | Indicates reentrancy guard reentrant call. |
| `SafeERC20FailedOperation` | `NFTFundRaiseOrderBook` | Indicates safe erc20 failed operation. Params: token: address. |
| `InvalidPair` | `TwapOracle` | Indicates an invalid pair value. |
| `NotKeeper` | `TwapOracle` | Indicates the required condition 'keeper' is not met. |
| `NotLpActivator` | `TwapOracle` | Indicates the required condition 'lp activator' is not met. |
| `PeriodNotElapsed` | `TwapOracle` | Indicates period not elapsed. Params: elapsed: uint256, required: uint256. |
| `PriceOverflow` | `TwapOracle` | Indicates price overflow. |
| `TwapAlreadyActive` | `TwapOracle` | Indicates twap already active. |
| `TwapNotActive` | `TwapOracle` | Indicates twap not active. |
| `ZeroAddress` | `TwapOracle` | Indicates that a zero address was provided. |
| `ZeroInitialPrice` | `TwapOracle` | Indicates zero initial price. |
| `ZeroStartTime` | `TwapOracle` | Indicates zero start time. |
| `ArcStakingDisabled` | `YieldPool` | Indicates arc staking disabled. |
| `ArrayLengthMismatch` | `YieldPool` | Indicates array length mismatch. |
| `BatchTooLarge` | `YieldPool` | Indicates batch too large. |
| `EmptyArray` | `YieldPool` | Indicates empty array. |
| `EmptyStakeIds` | `YieldPool` | Indicates empty stake ids. |
| `InvalidLpToken` | `YieldPool` | Indicates an invalid lp token value. |
| `LpModeAlreadyActive` | `YieldPool` | Indicates lp mode already active. |
| `LpModeNotActive` | `YieldPool` | Indicates lp mode not active. |
| `LpStakeNotActive` | `YieldPool` | Indicates lp stake not active. |
| `NoFrozenRewards` | `YieldPool` | Indicates no frozen rewards. |
| `NoRewardToClaim` | `YieldPool` | Indicates no reward to claim. |
| `NotLpActivator` | `YieldPool` | Indicates the required condition 'lp activator' is not met. |
| `NotLpStakeOwner` | `YieldPool` | Indicates the required condition 'lp stake owner' is not met. |
| `NotRewarder` | `YieldPool` | Indicates the required condition 'rewarder' is not met. |
| `NotStakeOwner` | `YieldPool` | Indicates the required condition 'stake owner' is not met. |
| `ReentrancyGuardReentrantCall` | `YieldPool` | Indicates reentrancy guard reentrant call. |
| `SafeERC20FailedOperation` | `YieldPool` | Indicates safe erc20 failed operation. Params: token: address. |
| `StakeForWindowClosed` | `YieldPool` | Indicates stake for window closed. |
| `StakeNotActive` | `YieldPool` | Indicates stake not active. |
| `StakeNotYetEligible` | `YieldPool` | Indicates stake not yet eligible. |
| `ZeroAddress` | `YieldPool` | Indicates that a zero address was provided. |
| `ZeroAmount` | `YieldPool` | Indicates zero amount. |
