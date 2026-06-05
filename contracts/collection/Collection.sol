// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {CollectionStorage} from "./CollectionCore/CollectionStorage.sol";
import {MintHelper} from "./CollectionCore/MintHelper.sol";
import {ClaimHelper} from "./CollectionCore/ClaimHelper.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {ERC1155} from "@openzeppelin/contracts/token/ERC1155/ERC1155.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

/**
 * @title NftFundRaiseCollection
 * @dev ERC1155 fund-raise collection where holders pay USDT to mint new tokens
 *      in successive claim rounds, each doubling the mintable supply per token ID.
 */
contract NftFundRaiseCollection is Ownable, ERC1155, ReentrancyGuard, CollectionStorage, MintHelper, ClaimHelper {
    /**
     * @param initialOwner Address of the initial owner.
     * @param usdtAddr     Address of the USDT token used for claim payments.
     */
    constructor(address initialOwner, address usdtAddr) ERC1155("") Ownable(initialOwner) {
        // initialOwner is validated by the Ownable constructor, which reverts on the
        // zero address before this body executes.
        require(usdtAddr != address(0), "Invalid USDT address");

        usdtToken = IERC20(usdtAddr);
        // The deployer holds setup privileges until it renounces the role.
        deployer = msg.sender;
    }

    /**
     * @dev Restrict a function to the deployer. Once the deployer renounces its role
     *      (sets `deployer` to address(0)), every deployer-gated function is permanently
     *      locked because msg.sender can never be the zero address.
     */
    modifier onlyDeployer() {
        require(msg.sender == deployer, "Not deployer");
        _;
    }

    // ─── User: Claiming ────────────────────────────────────────────────────────

    /**
     * @notice Claim tokens during an active claim round.
     *         Caller must hold the token and have approved this contract for USDT.
     * @param id     Token ID to claim.
     * @param amount Number of tokens to claim.
     */
    function claimTokens(uint256 id, uint256 amount) external nonReentrant {
        address caller = msg.sender;
        uint256 activeRound = claimRound;
        _validateClaimTokens(activeRound, caller, id, amount);

        ClaimRound memory round = claimRounds[activeRound];
        _handleClaimPayment(caller, round.usdtAmountPerNft, amount);
        _handleMintForClaim(caller, id, amount, activeRound);
    }

    // ─── Deployer: Minting ─────────────────────────────────────────────────────

    /**
     * @notice Batch-mint token IDs to `to`. Callable only by the deployer, so minting
     *         stops permanently once the deployer renounces its role.
     * @param to      Recipient address.
     * @param ids     Array of token IDs to mint.
     * @param amounts Array of amounts corresponding to each token ID.
     */
    function batchTokenMint(address to, uint256[] calldata ids, uint256[] calldata amounts) external onlyDeployer {
        _mintTokenBatch(to, ids, amounts);
    }

    // ─── Owner: Claim rounds ───────────────────────────────────────────────────

    /**
     * @notice Open a new claim round.
     * @param startTime        Unix timestamp for the round start (must be >= block.timestamp).
     * @param usdtAmountPerNft Wei amount of USDT charged per token minted in this round.
     */
    function addClaimRound(uint128 startTime, uint256 usdtAmountPerNft) external onlyOwner {
        _enableMintAndClaim(startTime, usdtAmountPerNft);
    }

    /**
     * @notice Mint all unclaimed tokens for multiple token IDs to the owner after a round ends.
     * @param roundId  ID of the (ended) claim round.
     * @param tokenIds Token IDs to sweep.
     */
    function batchOwnerClaim(uint256 roundId, uint256[] calldata tokenIds) external onlyOwner {
        _onlyWhenDeadlinePassed(roundId);
        for (uint256 i = 0; i < tokenIds.length; i++) {
            _handleOwnerClaim(roundId, tokenIds[i]);
        }
    }

    // ─── Deployer: Configuration ───────────────────────────────────────────────

    /**
     * @notice Set per-token URIs in bulk. Callable only by the deployer, so URIs are
     *         frozen permanently once the deployer renounces its role.
     * @param ids  Token IDs.
     * @param uris Corresponding URI strings.
     */
    function setURIs(uint256[] calldata ids, string[] calldata uris) external onlyDeployer {
        require(ids.length == uris.length, "Length mismatch");
        uint256 len = ids.length;
        for (uint256 i = 0; i < len; i++) {
            _setTokenURI(ids[i], uris[i]);
        }
    }

    /**
     * @notice Authorise a single external address (e.g. the order book) to transfer tokens.
     *         Callable only by the deployer, so the allowlist is frozen permanently once
     *         the deployer renounces its role.
     * @param newAddress The address to authorise.
     */
    function addTransferAllowedAddress(address newAddress) external onlyDeployer {
        require(newAddress != address(0), "Invalid address");
        orderBookAddress = newAddress;
    }

    // ─── Deployer: Role ────────────────────────────────────────────────────────

    /**
     * @notice Permanently renounce the deployer role by setting `deployer` to address(0).
     *         After this, batchTokenMint, setURIs and addTransferAllowedAddress can never
     *         be called again.
     */
    function renounceDeployer() external onlyDeployer {
        deployer = address(0);
    }

    // ─── View helpers ──────────────────────────────────────────────────────────

    /**
     * @notice Number of tokens minted in `roundId` for `tokenId`.
     */
    function mintedInRoundFor(uint256 roundId, uint256 tokenId) external view returns (uint256) {
        return mintedInRound[roundId][tokenId];
    }

    /**
     * @notice Number of tokens `acct` has claimed in `roundId` for `tokenId`.
     */
    function alreadyClaimedInRound(uint256 roundId, uint256 tokenId, address acct) external view returns (uint256) {
        return claimedPerRound[roundId][tokenId][acct];
    }

    // ─── Internal helpers ──────────────────────────────────────────────────────

    function isTransferAllowed(address addr) internal view returns (bool) {
        return (addr == owner() || addr == orderBookAddress);
    }

    // ─── Overrides ─────────────────────────────────────────────────────────────

    /**
     * @dev Allow ownership to be transferred exactly once.
     *      Subsequent calls revert regardless of who calls.
     */
    function transferOwnership(address newOwner) public override onlyOwner {
        if (ownershipFlag) revert("Ownership has already been transferred");
        ownershipFlag = true;
        super.transferOwnership(newOwner);
    }

    /**
     * @dev Renouncing ownership is permanently disabled.
     *      Without an owner, USDT from claims would be sent to address(0) and all
     *      admin functions would be permanently locked.
     */
    function renounceOwnership() public pure override {
        revert("Renouncing ownership is disabled");
    }

    /**
     * @dev Restrict token transfers to: mints (from == address(0)), the owner,
     *      the authorised order book address, or any operator approved by them.
     */
    function _update(address from, address to, uint256[] memory ids, uint256[] memory values) internal override {
        require(
            from == address(0) || isTransferAllowed(from) || isTransferAllowed(to) || isTransferAllowed(msg.sender),
            "Not allowed to transfer"
        );
        super._update(from, to, ids, values);
    }

    /**
     * @dev Return the per-token URI stored for `id`.
     */
    function uri(uint256 id) public view override returns (string memory) {
        return _tokenURIs[id];
    }
}
