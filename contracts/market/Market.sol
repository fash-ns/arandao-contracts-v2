// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

import {IMarketToken} from "./IMarketToken.sol";
import {MarketLib} from "./MarketLib.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {ICreateOrder} from "./ICreateOrder.sol";

import {Initializable} from "@openzeppelin/contracts/proxy/utils/Initializable.sol";
import {OwnableUpgradeable} from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import {UUPSUpgradeable} from "@openzeppelin/contracts/proxy/utils/UUPSUpgradeable.sol";

contract DMarket is Initializable, OwnableUpgradeable, UUPSUpgradeable {
    address public marketTokenAddress;
    address public purchaseTokenAddress;
    address public arcAddress;
    address public gatewayAddress;
    uint256 private constant lockDnmAmount = 2 ether;
    uint256 upgradeDeadline;
    mapping(uint256 => MarketLib.Product) public products;
    mapping(address => uint256) public sellerLockedArcTime;
    bool ownershipTransferredFlag;

    constructor() {
        _disableInitializers();
    }

    modifier inUpgradeTime {
        require(upgradeDeadline >= block.timestamp, "The upgrade allowed time has been passed.");
        _;
    }

    function initialize(address initialOwner, address _marketTokenAddress) public initializer {
        __Ownable_init(initialOwner);

        marketTokenAddress = _marketTokenAddress;
        upgradeDeadline = block.timestamp + 90 days;
    }

    function extendUpgradableDeadline() public onlyOwner {
        upgradeDeadline += 90 days;
    }

    function _authorizeUpgrade(address newImplementation)
        internal
        override
        onlyOwner
        inUpgradeTime
    {}

    function setMarketTokenAddress(
        address _marketTokenAddress,
        address _purchaseTokenAddress,
        address _dnmAddress,
        address _gatewayAddress
    ) public onlyOwner {
        require(arcAddress == address(0), "Addresses are already set.");
        marketTokenAddress = _marketTokenAddress;
        purchaseTokenAddress = _purchaseTokenAddress;
        arcAddress = _dnmAddress;
        gatewayAddress = _gatewayAddress;
    }

    function lockSellerArc() public {
        address sellerAddress = msg.sender;
        require(
            sellerLockedArcTime[sellerAddress] == 0,
            "Seller has already locked ARC"
        );
        IERC20 dnmContract = IERC20(arcAddress);
        uint256 dnmBalance = dnmContract.balanceOf(sellerAddress);
        require(
            dnmBalance >= lockDnmAmount,
            "Seller has less ARC balance than required."
        );
        dnmContract.transferFrom(sellerAddress, address(this), lockDnmAmount);
        sellerLockedArcTime[sellerAddress] = block.timestamp;
        emit MarketLib.SellerLockedArc(sellerAddress);
    }

    function withdrawSellerArc() public {
        require(
            sellerLockedArcTime[msg.sender] != 0,
            "Seller ARC is not locked"
        );
        require(
            block.timestamp > sellerLockedArcTime[msg.sender] + 365 days,
            "Seller ARC must be locked for at least 1 year."
        );

        IERC20 dnmContract = IERC20(arcAddress);
        sellerLockedArcTime[msg.sender] = 0;
        dnmContract.transfer(msg.sender, lockDnmAmount);
        emit MarketLib.SellerWithdrawnArc(msg.sender);
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
        uint256 tokenId = marketTokenContract.mint(
            msg.sender,
            quantity,
            ipfsCid
        );
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

    /**
     * @dev Override transferOwnership to allow only one transfer.
     */
    function transferOwnership(address newOwner) public override onlyOwner {
        if (ownershipTransferredFlag == false) {
            super.transferOwnership(newOwner);
            ownershipTransferredFlag = true;
        } else {
            revert("Ownership has already been transferred");
        }
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

            if (sellerLockedArcTime[product.sellerAddress] == 0)
                revert MarketLib.MarketSellerDnmNotLocked(
                    product.sellerAddress
                );

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
            uint256 sellerShare = MarketLib.getSellerShare(
                product.bv,
                product.sv
            );
            bool isSellerTransferSuccessful = purchaseTokenContract
                .transferFrom(
                    msg.sender,
                    product.sellerAddress,
                    sellerShare * quantity
                );
            require(
                isSellerTransferSuccessful,
                "Couldn't transfer seller share"
            );
            bool isBVTransferSuccessful = purchaseTokenContract.transferFrom(
                msg.sender,
                address(this),
                requiredBalance - (sellerShare * quantity)
            );
            require(
                isBVTransferSuccessful,
                "Couldn't transfer BV share to market"
            );
            bool isCoreApprovalSuccessful = purchaseTokenContract.approve(
                gatewayAddress,
                requiredBalance - (sellerShare * quantity)
            );
            require(
                isCoreApprovalSuccessful,
                "Couldn't approve core to consume BV"
            );

            totalCoreTransferAmount += (requiredBalance -
                (sellerShare * quantity));
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
