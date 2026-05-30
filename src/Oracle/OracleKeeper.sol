// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {
    AutomationCompatibleInterface
} from "@chainlink/contracts/src/v0.8/automation/interfaces/AutomationCompatibleInterface.sol";
import {OwnerIsCreator} from "@chainlink/contracts/src/v0.8/shared/access/OwnerIsCreator.sol";

interface ITwapOracle {
    function update() external;
    function updateReady() external view returns (bool);
}

/**
 * @title OracleKeeper
 * @notice Chainlink Automation-compatible upkeep contract that periodically triggers
 *         a TwapOracle update.
 *
 *  Workflow
 *  ────────
 *  1. Deploy, pointing at an already-deployed TwapOracle.
 *  2. Register this contract as a Chainlink upkeep.
 *  3. Call setForwarderAddress() with the forwarder address Chainlink assigns to
 *     this upkeep — only that address may call performUpkeep().
 *  4. Chainlink nodes call checkUpkeep() off-chain; when it returns true (the oracle
 *     is ready for an update), they call performUpkeep() on-chain, which forwards the
 *     call to TwapOracle.update().
 */
contract OracleKeeper is AutomationCompatibleInterface, OwnerIsCreator {
    // ─── State ──────────────────────────────────────────────────────────────────

    /// @notice Target TWAP oracle whose update() this keeper drives.
    ITwapOracle public immutable oracle;

    /// @notice Chainlink forwarder address for this upkeep registration.
    ///         Only this address may call performUpkeep().
    address public forwarderAddress;

    /// @notice Block timestamp of the last successful performUpkeep() call.
    uint256 public lastTimeStamp;

    // ─── Events ─────────────────────────────────────────────────────────────────

    event ForwarderSet(address indexed forwarder);
    event UpkeepPerformed(uint256 timestamp);

    // ─── Errors ─────────────────────────────────────────────────────────────────

    error ZeroAddress();
    error NotForwarder();

    // ─── Constructor ────────────────────────────────────────────────────────────

    /**
     * @param _oracle  Address of the deployed TwapOracle contract.
     */
    constructor(address _oracle) {
        if (_oracle == address(0)) revert ZeroAddress();
        oracle = ITwapOracle(_oracle);
        lastTimeStamp = block.timestamp;
    }

    // ─── Chainlink Automation ───────────────────────────────────────────────────

    /**
     * @notice Called off-chain by Chainlink nodes to check whether upkeep is needed.
     * @return upkeepNeeded  True when the oracle's PERIOD has elapsed and update() can be called.
     */
    function checkUpkeep(bytes calldata) external view override returns (bool upkeepNeeded, bytes memory performData) {
        upkeepNeeded = oracle.updateReady();
        performData = bytes("");
    }

    /**
     * @notice Called by the Chainlink forwarder to push a TWAP snapshot.
     * @dev    Reverts if called by any address other than the registered forwarder.
     *         The oracle's own PERIOD guard is the authoritative time check; this
     *         function does not duplicate it.
     */
    function performUpkeep(bytes calldata) external override {
        if (msg.sender != forwarderAddress) revert NotForwarder();
        oracle.update();
        lastTimeStamp = block.timestamp;
        emit UpkeepPerformed(block.timestamp);
    }

    // ─── Admin ──────────────────────────────────────────────────────────────────

    /**
     * @notice Sets the Chainlink forwarder address that is authorised to call performUpkeep().
     * @dev    Obtain this address from the Chainlink Automation UI after registering the upkeep.
     * @param  _forwarder  Forwarder address assigned by Chainlink to this upkeep.
     */
    function setForwarderAddress(address _forwarder) external onlyOwner {
        if (_forwarder == address(0)) revert ZeroAddress();
        forwarderAddress = _forwarder;
        emit ForwarderSet(_forwarder);
    }
}
