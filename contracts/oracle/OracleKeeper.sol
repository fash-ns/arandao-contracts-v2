// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

import {ITwapOracle} from "./ITwapOracle.sol";

/**
 * @title OracleKeeper
 * @notice Permissioned driver for TwapOracle.update() with a minimum interval gate.
 *
 *  Workflow
 *  ────────
 *  1. Deploy, pointing at an already-deployed TwapOracle.
 *  2. Owner whitelists caller address(es) via setForwarder(addr, true)
 *     (EOA bot, multisig, or a future CRE receiver contract).
 *  3. An allowed forwarder calls updateOracle(), which enforces MIN_INTERVAL
 *     then forwards to TwapOracle.update(). TwapOracle.PERIOD remains independent.
 *
 *  A Chainlink CRE IReceiver can be deployed separately later and whitelisted
 *  here as a forwarder when CRE is ready.
 */
contract OracleKeeper is Ownable {
    // ─── Constants ──────────────────────────────────────────────────────────────

    /// @notice Minimum wall-clock gap between successful updates.
    uint256 public constant MIN_INTERVAL = 1 days;

    // ─── State ──────────────────────────────────────────────────────────────────

    /// @notice Target TWAP oracle whose update() this keeper drives.
    ITwapOracle public immutable oracle;

    /// @notice Addresses authorised to call updateOracle().
    mapping(address => bool) public allowedForwarders;

    /// @notice Block timestamp of the last successful updateOracle() call.
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

    // ─── Update ─────────────────────────────────────────────────────────────────

    /**
     * @notice Pushes a TWAP oracle update. Only whitelisted forwarders may call.
     * @dev    Enforces MIN_INTERVAL before calling oracle.update().
     */
    function updateOracle() external {
        if (!allowedForwarders[msg.sender]) revert NotForwarder();

        if (lastTimeStamp != 0) {
            uint256 elapsed = block.timestamp - lastTimeStamp;
            if (elapsed < MIN_INTERVAL) revert UpdateTooSoon(elapsed, MIN_INTERVAL);
        }

        oracle.update();
        lastTimeStamp = block.timestamp;
        emit OracleUpdated(block.timestamp);
    }

    // ─── Views ──────────────────────────────────────────────────────────────────

    /**
     * @notice True when a forwarder may successfully call updateOracle() right now.
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
     * @notice Adds or removes an address authorised to call updateOracle().
     * @param  forwarder  Caller to update (EOA, bot, or future CRE receiver).
     * @param  allowed    True to whitelist, false to revoke.
     */
    function setForwarder(address forwarder, bool allowed) external onlyOwner {
        if (forwarder == address(0)) revert ZeroAddress();
        allowedForwarders[forwarder] = allowed;
        emit ForwarderUpdated(forwarder, allowed);
    }
}
