// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

import {IMarketToken} from "./IMarketToken.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {MarketLib} from "./MarketLib.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

contract AranDAOMarket is Ownable {
  address public marketTokenAddress;
  address public purchaseTokenAddress;
  address public dnmAddress;
  address public gatewayAddress;
  mapping(uint256 => MarketLib.Product) public products;
  mapping(address => bool) public sellerLockedDnm;

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

  function lockSellerDnm(address sellerAddress) internal {
    IERC20 dnmContract = IERC20(dnmAddress);
    uint256 dnmBalance = dnmContract.balanceOf(sellerAddress);
    require(dnmBalance >= 1 ether, "Seller has less than 1 DNM balance");
    dnmContract.transferFrom(sellerAddress, address(this), 1 ether);
    sellerLockedDnm[sellerAddress] = true;
    emit MarketLib.SellerLockedDnm(sellerAddress);
  }

  function withdrawSellerDnm() public {
    require(sellerLockedDnm[msg.sender], "Seller DNM is not locked");

    IERC20 dnmContract = IERC20(dnmAddress);
    dnmContract.transferFrom(address(this), msg.sender, 1 ether);
    sellerLockedDnm[msg.sender] = false;
    emit MarketLib.SellerWithdrawnDnm(msg.sender);
  }

  function createProduct(
    uint256 bv,
    uint256 uv,
    uint256 quantity,
    string memory ipfsCid
  ) public {
    if (!sellerLockedDnm[msg.sender]) lockSellerDnm(msg.sender);

    IMarketToken marketTokenContract = IMarketToken(marketTokenAddress);
    uint256 tokenId = marketTokenContract.mint(msg.sender, quantity, ipfsCid);
    products[tokenId] = MarketLib.Product(msg.sender, bv, uv);
    emit MarketLib.ProductCreated(msg.sender, tokenId, bv, uv);
  }

  function purchaseProduct(
    MarketLib.PurchaseProduct[] memory purchaseProducts,
    address parentAddress
  ) public {
    IMarketToken marketTokenContract = IMarketToken(marketTokenAddress);

    MarketLib.Product[] memory _products = new MarketLib.Product[](
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

      if (!sellerLockedDnm[product.sellerAddress])
        revert MarketLib.MarketSellerDnmNotLocked(product.sellerAddress);

      IERC20 purchaseTokenContract = IERC20(purchaseTokenAddress);
      uint256 userBalance = purchaseTokenContract.balanceOf(msg.sender);
      uint256 requiredBalance = MarketLib.calculatePayablePriceOfProduct(
        product.bv,
        product.uv
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

      uint256 sellerShare = MarketLib.getSellerShare(product.bv, product.uv);
      purchaseTokenContract.transferFrom(
        msg.sender,
        product.sellerAddress,
        sellerShare * quantity
      );
      purchaseTokenContract.transferFrom(
        msg.sender,
        gatewayAddress,
        requiredBalance - (sellerShare * quantity)
      );

      marketTokenContract.safeTransferFrom(
        product.sellerAddress,
        msg.sender,
        tokenId,
        quantity,
        bytes("")
      );

      _products[i] = product;
    }

    //TODO: Make gateway order. with products array.
  }
}
