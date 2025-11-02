// SPDX-License-Identifier: MIT
// Compatible with OpenZeppelin Contracts ^5.4.0
pragma solidity ^0.8.30;

import {ERC1155} from "@openzeppelin/contracts/token/ERC1155/ERC1155.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {CollectionStorage} from "./CollectionCore/CollectionStorage.sol";
import {MintHelper} from "./CollectionCore/MintHelper.sol";
import {ClaimHelper} from "./CollectionCore/ClaimHelper.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

contract ArcCollection is Ownable, ERC1155, ReentrancyGuard, CollectionStorage, MintHelper, ClaimHelper {
    /// @notice Constructor to set initial owner, DAI token address, and metadata URI.
    constructor(address initialOwner, address daiAddr, string memory uri) ERC1155(uri) Ownable(initialOwner) {
        daiToken = IERC20(daiAddr);
    }

    /**
     * @notice Claim tokens during an active claim round.
     * @param id Token ID to claim.
     * @param amount Number of tokens to claim.
     */
    function claimTokens(uint256 id, uint256 amount) external nonReentrant {
        address caller = msg.sender;
        uint256 activeRound = claimRound; // active round id, must be > 0 after _enableMintAndClaim
        _validateClaimTokens(activeRound, caller, id, amount);

        ClaimRound memory round = claimRounds[activeRound];
        _handleMintForClaim(caller, id, amount, activeRound);
        _handleClaimPayment(caller, round.daiAmountPerNft, amount);
    }

    /**
     * @notice Owner performs initial minting of tokens to multiple recipients.
     * @param recipients Array of recipient addresses.
     * @param ids Array of token IDs to mint.
     * @param amounts Array of amounts to mint for each token ID.
     */
    function batchTokenMint(address[] calldata recipients, uint256[] calldata ids, uint256[] calldata amounts)
        external
        onlyOwner
    {
        _mintTokenBatch(recipients, ids, amounts);
    }

    /**
     * @notice Owner mints tokens to a specific recipient.
     * @param recipient Address of the recipient.
     * @param id Token ID to mint.
     * @param amount Amount of tokens to mint.
     */
    function tokenMint(address recipient, uint256 id, uint256 amount) external onlyOwner {
        _mintToken(recipient, id, amount);
    }

    /**
     * @notice Owner claims unclaimed tokens after a claim round has ended.
     * @param roundId ID of the claim round.
     * @param tokenId Token ID to claim unclaimed tokens for.
     */
    function claimByOwner(uint256 roundId, uint256 tokenId) external onlyOwner {
        _onlyWhenDeadlinePassed(roundId);
        _handleOwnerClaim(roundId, tokenId);
    }

    /**
     * @notice Owner claims unclaimed tokens for multiple token IDs in a batch.
     */
    function batchOwnerClaim(uint256 roundId, uint256[] calldata tokenIds) external onlyOwner {
        _onlyWhenDeadlinePassed(roundId);

        for (uint256 i = 0; i < tokenIds.length; i++) {
            _handleOwnerClaim(roundId, tokenIds[i]);
        }
    }

    /**
     * @dev Add a new claim round.
     */
    function addClaimRound(uint128 startTime, uint256 daiAmountPerToken) external onlyOwner {
        _enableMintAndClaim(startTime, daiAmountPerToken);
    }

    /**
     * @dev Set a new URI for all token types.
     */
    function setURI(string memory newuri) external onlyOwner {
        _setURI(newuri);
    }

    /**
     * @dev Add an address to the transfer allowed list.
     */
    function addTransferAllowedAddress(address newAddress) external onlyOwner {
        require(newAddress != address(0), "Invalid address");
        require(!transferAllowed[newAddress], "Already authorized");
        transferAllowed[newAddress] = true;
    }

    /**
     * @dev Remove an address from the transfer allowed list.
     */
    function removeTransferAllowedAddress(address addr) external onlyOwner {
        require(transferAllowed[addr], "Not authorized");
        transferAllowed[addr] = false;
    }

    /**
     * @notice how many were minted in a round for a tokenId
     */
    function mintedInRoundFor(uint256 roundId, uint256 tokenId) external view returns (uint256) {
        return mintedInRound[roundId][tokenId];
    }

    /**
     * @notice how many tokens an account has already claimed in a round for a tokenId
     */
    function alreadyClaimedInRound(uint256 roundId, uint256 tokenId, address acct) external view returns (uint256) {
        return claimedPerRound[roundId][tokenId][acct];
    }

    // ------ OVERRIDES ------
    /**
     * @dev Override transferOwnership to allow only one transfer.
     */
    function transferOwnership(address newOwner) public override onlyOwner {
        if (ownershipFlag == false) {
            super.transferOwnership(newOwner);
            ownershipFlag = true;
        } else {
            revert("Ownership has already been transferred");
        }
    }

    /**
     * @dev Override to restrict transfers to allowed addresses unless minting/burning.
     */
    function _update(address from, address to, uint256[] memory ids, uint256[] memory values) internal override {
        require(
            transferAllowed[from] || transferAllowed[to] || transferAllowed[msg.sender] || from == address(0),
            "Not allowed to transfer"
        );
        super._update(from, to, ids, values);
    }
}
