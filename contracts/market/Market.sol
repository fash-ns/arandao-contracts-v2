// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

import {IMarketToken} from "./IMarketToken.sol";
import {MarketLib} from "./MarketLib.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {ICreateOrder} from "./ICreateOrder.sol";

contract DMarket {
  using SafeERC20 for IERC20;

  address public marketTokenAddress;
  address public purchaseTokenAddress;
  address public arcAddress;
  address public coreAddress;
  uint256 private constant lockArcAmount = 1 ether;
  mapping(uint256 => MarketLib.Product) public products;
  mapping(address => uint256) public sellerLockedArcTime;

  constructor(
    address _marketTokenAddress,
    address _purchaseTokenAddress,
    address _arcAddress,
    address _coreAddress
  ) {
    marketTokenAddress = _marketTokenAddress;
    purchaseTokenAddress = _purchaseTokenAddress;
    arcAddress = _arcAddress;
    coreAddress = _coreAddress;
  }

  function lockSellerArc() public {
    address sellerAddress = msg.sender;
    require(
      sellerLockedArcTime[sellerAddress] == 0,
      "Seller has already locked ARC"
    );
    IERC20 arcContract = IERC20(arcAddress);
    uint256 arcBalance = arcContract.balanceOf(sellerAddress);
    require(
      arcBalance >= lockArcAmount,
      "Seller has less ARC balance than required."
    );
    arcContract.safeTransferFrom(sellerAddress, address(this), lockArcAmount);
    sellerLockedArcTime[sellerAddress] = block.timestamp;
    emit MarketLib.SellerLockedArc(
      sellerAddress,
      lockArcAmount,
      block.timestamp
    );
  }

  function withdrawSellerArc() public {
    require(sellerLockedArcTime[msg.sender] != 0, "Seller ARC is not locked");
    require(
      block.timestamp > sellerLockedArcTime[msg.sender] + 365 days,
      "Seller ARC must be locked for at least 1 year."
    );

    IERC20 arcContract = IERC20(arcAddress);
    sellerLockedArcTime[msg.sender] = 0;
    arcContract.safeTransfer(msg.sender, lockArcAmount);
    emit MarketLib.SellerWithdrawnArc(msg.sender, lockArcAmount);
  }

  function createProduct(
    uint256 bv,
    uint256 sv,
    uint256 quantity,
    string memory ipfsCid
  ) public {
    require(
      sellerLockedArcTime[msg.sender] != 0,
      "User has not locked ARC yet"
    );

    require(sv >= bv / 100, "SV Should be greater than 1 percent of BV.");

    IMarketToken marketTokenContract = IMarketToken(marketTokenAddress);
    uint256 tokenId = marketTokenContract.mint(msg.sender, quantity, ipfsCid);
    products[tokenId] = MarketLib.Product(msg.sender, bv, sv, true);
    emit MarketLib.ProductCreated(msg.sender, tokenId, bv, sv, quantity);
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

      require(
        product.sellerAddress != msg.sender,
        "User cannot purchase his own product."
      );

      if (!product.active) {
        revert MarketLib.MarketProductInactive(tokenId);
      }

      if (sellerLockedArcTime[product.sellerAddress] == 0)
        revert MarketLib.MarketSellerArcNotLocked(product.sellerAddress);

      IERC20 purchaseTokenContract = IERC20(purchaseTokenAddress);
      uint256 userBalance = purchaseTokenContract.balanceOf(msg.sender);
      uint256 requiredBalance =
        MarketLib.calculatePayablePriceOfProduct(product.bv, product.sv) *
          quantity;
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
      purchaseTokenContract.safeTransferFrom(
        msg.sender,
        product.sellerAddress,
        sellerShare * quantity
      );
      purchaseTokenContract.safeTransferFrom(
        msg.sender,
        address(this),
        requiredBalance - (sellerShare * quantity)
      );
      purchaseTokenContract.forceApprove(
        coreAddress,
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
        sv: product.sv * quantity,
        bv: product.bv * quantity
      });

      emit MarketLib.ProductPurchased(msg.sender, tokenId, quantity);
    }
    ICreateOrder createOrderContract = ICreateOrder(coreAddress);
    createOrderContract.createOrder(
      msg.sender,
      parentAddress,
      position,
      _products,
      totalCoreTransferAmount
    );
    emit MarketLib.PurchaseCompleted(
      msg.sender,
      parentAddress,
      position,
      totalCoreTransferAmount,
      purchaseProducts.length
    );
  }
}
