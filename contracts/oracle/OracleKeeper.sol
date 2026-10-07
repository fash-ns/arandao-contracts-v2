// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {IERC165} from "@openzeppelin/contracts/utils/introspection/IERC165.sol";

import {IReceiver} from "./interfaces/IReceiver.sol";
import {ITwapOracle} from "./ITwapOracle.sol";

/**
 * @title OracleKeeper
 * @notice CRE Keystone consumer that periodically triggers a TwapOracle update.
 *
 *  Workflow
 *  ────────
 *  1. Deploy, pointing at an already-deployed TwapOracle.
 *  2. Deploy a CRE workflow that cron-triggers weekly and calls
 *     `evmClient.writeReport` targeting this contract (IReceiver.onReport).
 *  3. Owner whitelists the KeystoneForwarder address(es) for the target
 *     network via setForwarder(forwarder, true).
 *  4. On each report, this contract enforces MIN_INTERVAL then
 *     forwards to TwapOracle.update(). TwapOracle.PERIOD remains independent.
 */
contract OracleKeeper is IReceiver, Ownable {
    // ─── Constants ──────────────────────────────────────────────────────────────

    /// @notice Minimum wall-clock gap between successful CRE-driven updates.
    /// @dev    CRE cron should target ~weekly; this is the on-chain floor.
    uint256 public constant MIN_INTERVAL = 3 days;

    // ─── State ──────────────────────────────────────────────────────────────────

    /// @notice Target TWAP oracle whose update() this keeper drives.
    ITwapOracle public immutable oracle;

    /// @notice Keystone / MockKeystone forwarders authorised to call onReport.
    mapping(address => bool) public allowedForwarders;

    /// @notice Block timestamp of the last successful onReport update.
    /// @dev    Zero until the first successful update (first call is not gated).
    uint256 public lastTimeStamp;

    // ─── Events ─────────────────────────────────────────────────────────────────

    event ForwarderUpdated(address indexed forwarder, bool allowed);
    event OracleUpdated(uint256 timestamp);

    // ─── Errors ─────────────────────────────────────────────────────────────────

    error ZeroAddress();
    error NotForwarder();
    error UpdateTooSoon(uint256 elapsed, uint256 required);

    // ─── Constructor ────────────────────────────────────────────────────────────

    /**
     * @param _oracle  Address of the deployed TwapOracle contract.
     */
    constructor(address _oracle) Ownable(msg.sender) {
        if (_oracle == address(0)) revert ZeroAddress();
        oracle = ITwapOracle(_oracle);
    }

    // ─── CRE IReceiver ──────────────────────────────────────────────────────────

    /**
     * @notice Receives a CRE Keystone report and pushes a TWAP oracle update.
     * @dev    Only whitelisted forwarders may call. Report payload is ignored —
     *         the workflow only needs to deliver a verified write. Enforces
     *         MIN_INTERVAL before calling oracle.update().
     * @param  metadata  Forwarder-supplied workflow metadata (unused).
     * @param  report    ABI-encoded workflow payload (unused).
     */
    function onReport(bytes calldata metadata, bytes calldata report) external override {
        metadata;
        report;

        if (!allowedForwarders[msg.sender]) revert NotForwarder();

        if (lastTimeStamp != 0) {
            uint256 elapsed = block.timestamp - lastTimeStamp;
            if (elapsed < MIN_INTERVAL) revert UpdateTooSoon(elapsed, MIN_INTERVAL);
        }

        oracle.update();
        lastTimeStamp = block.timestamp;
        emit OracleUpdated(block.timestamp);
    }

    /// @inheritdoc IERC165
    function supportsInterface(bytes4 interfaceId) public pure override returns (bool) {
        return interfaceId == type(IReceiver).interfaceId || interfaceId == type(IERC165).interfaceId;
    }

    // ─── Views ──────────────────────────────────────────────────────────────────

    /**
     * @notice True when a forwarder may successfully call onReport right now.
     * @dev    Combines the keeper MIN_INTERVAL gate with the oracle's own readiness.
     */
    function canUpdate() external view returns (bool) {
        if (lastTimeStamp != 0 && block.timestamp - lastTimeStamp < MIN_INTERVAL) {
            return false;
        }
        return oracle.updateReady();
    }

    // ─── Admin ──────────────────────────────────────────────────────────────────

    /**
     * @notice Adds or removes a KeystoneForwarder authorised to call onReport.
     * @dev    Use the production KeystoneForwarder for the target chain, or
     *         MockKeystoneForwarder during CRE simulation.
     * @param  forwarder  Forwarder address to update.
     * @param  allowed    True to whitelist, false to revoke.
     */
    function setForwarder(address forwarder, bool allowed) external onlyOwner {
        if (forwarder == address(0)) revert ZeroAddress();
        allowedForwarders[forwarder] = allowed;
        emit ForwarderUpdated(forwarder, allowed);
    }
}
