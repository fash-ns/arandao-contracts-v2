// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

import {IMarketToken} from "./IMarketToken.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {MarketLib} from "./MarketLib.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {ICreateOrder} from "./ICreateOrder.sol";

contract AranDAOMarket is Ownable {
  address public marketTokenAddress;
  address public purchaseTokenAddress;
  address public dnmAddress;
  address public gatewayAddress;
  uint256 private constant lockDnmAmount = 4 ether;
  mapping(uint256 => MarketLib.Product) public products;
  mapping(address => uint256) public sellerLockedDnmTime;

  constructor(address _marketTokenAddress) Ownable(msg.sender) {
    marketTokenAddress = _marketTokenAddress;
  }

  function setMarketTokenAddress(
    address _marketTokenAddress,
    address _purchaseTokenAddress,
    address _dnmAddress,
    address _gatewayAddress
  ) public onlyOwner {
    marketTokenAddress = _marketTokenAddress;
    purchaseTokenAddress = _purchaseTokenAddress;
    dnmAddress = _dnmAddress;
    gatewayAddress = _gatewayAddress;
  }

  function lockSellerDnm(address sellerAddress) public {
    IERC20 dnmContract = IERC20(dnmAddress);
    uint256 dnmBalance = dnmContract.balanceOf(sellerAddress);
    require(dnmBalance >= lockDnmAmount, "Seller has less than 4 ARC balance");
    dnmContract.transferFrom(sellerAddress, address(this), lockDnmAmount);
    sellerLockedDnmTime[sellerAddress] = block.timestamp;
    emit MarketLib.SellerLockedDnm(sellerAddress);
  }

  function withdrawSellerDnm() public {
    require(sellerLockedDnmTime[msg.sender] != 0, "Seller ARC is not locked");
    require(block.timestamp > sellerLockedDnmTime[msg.sender] + 365 days, "Seller ARC must be locked for at least 1 year.");

    IERC20 dnmContract = IERC20(dnmAddress);
    sellerLockedDnmTime[msg.sender] = 0;
    dnmContract.transfer(msg.sender, lockDnmAmount);
    emit MarketLib.SellerWithdrawnDnm(msg.sender);
  }

  function createProduct(
    uint256 bv,
    uint256 sv,
    uint256 quantity,
    string memory ipfsCid
  ) public {
    if (sellerLockedDnmTime[msg.sender] == 0) lockSellerDnm(msg.sender);

    IMarketToken marketTokenContract = IMarketToken(marketTokenAddress);
    uint256 tokenId = marketTokenContract.mint(msg.sender, quantity, ipfsCid);
    products[tokenId] = MarketLib.Product(msg.sender, bv, sv, true);
    emit MarketLib.ProductCreated(msg.sender, tokenId, bv, sv);
  }

  function setProductStatus(uint256 tokenId, bool status) public {
    MarketLib.Product storage product = products[tokenId];
    require(product.sellerAddress != address(0), "Product not found");
    require(
      product.sellerAddress == msg.sender,
      "Only seller can toggle product status"
    );

    product.active = status;

    emit MarketLib.ProductStatusChanged(tokenId, status);
  }

  function purchaseProduct(
    MarketLib.PurchaseProduct[] memory purchaseProducts,
    address parentAddress,
    uint8 position
  ) public {
    IMarketToken marketTokenContract = IMarketToken(marketTokenAddress);

    uint256 totalCoreTransferAmount = 0;

    ICreateOrder.CreateOrderStruct[]
      memory _products = new ICreateOrder.CreateOrderStruct[](
        purchaseProducts.length
      );

    for (uint256 i = 0; i < purchaseProducts.length; i++) {
      uint256 tokenId = purchaseProducts[i].productId;
      uint256 quantity = purchaseProducts[i].quantity;
      MarketLib.Product memory product = products[tokenId];
      require(product.sellerAddress != address(0), "Product not found");

      // require(
      //   product.sellerAddress != msg.sender,
      //   "User cannot purchase his own product."
      // );

      if (!product.active) {
        revert MarketLib.MarketProductInactive(tokenId);
      }

      if (sellerLockedDnmTime[product.sellerAddress] == 0)
        revert MarketLib.MarketSellerDnmNotLocked(product.sellerAddress);

      IERC20 purchaseTokenContract = IERC20(purchaseTokenAddress);
      uint256 userBalance = purchaseTokenContract.balanceOf(msg.sender);
      uint256 requiredBalance = MarketLib.calculatePayablePriceOfProduct(
        product.bv,
        product.sv
      ) * quantity;
      if (userBalance < requiredBalance)
        revert MarketLib.MarketBuyerInsufficientBalance(
          requiredBalance,
          userBalance
        );

      uint256 sellerProductBalance = marketTokenContract.balanceOf(
        product.sellerAddress,
        tokenId
      );
      if (sellerProductBalance < quantity)
        revert MarketLib.MarketSellerInsufficientBalance(
          quantity,
          sellerProductBalance
        );

      uint256 sellerShare = MarketLib.getSellerShare(product.bv, product.sv);
      purchaseTokenContract.transferFrom(
        msg.sender,
        product.sellerAddress,
        sellerShare * quantity
      );
      purchaseTokenContract.approve(
        gatewayAddress,
        requiredBalance - (sellerShare * quantity)
      );

      totalCoreTransferAmount += (requiredBalance - (sellerShare * quantity));

      marketTokenContract.safeTransferFrom(
        product.sellerAddress,
        msg.sender,
        tokenId,
        quantity,
        bytes("")
      );

      _products[i] = ICreateOrder.CreateOrderStruct({
        sellerAddress: product.sellerAddress,
        bv: product.bv,
        sv: product.sv
      });

      emit MarketLib.ProductPurchased(tokenId, quantity);
    }

    ICreateOrder createOrderContract = ICreateOrder(gatewayAddress);
    createOrderContract.createOrder(
      msg.sender,
      parentAddress,
      position,
      _products,
      totalCoreTransferAmount
    );
  }
}
