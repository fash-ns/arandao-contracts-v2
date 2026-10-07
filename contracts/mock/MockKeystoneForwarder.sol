// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {IERC165} from "@openzeppelin/contracts/utils/introspection/IERC165.sol";
import {IReceiver} from "../oracle/interfaces/IReceiver.sol";

/**
 * @title MockKeystoneForwarder
 * @notice Minimal stand-in for CRE KeystoneForwarder / MockKeystoneForwarder.
 * @dev    Mirrors the production delivery path used by CRE writeReport:
 *         1) ERC-165 probe for IReceiver
 *         2) Call receiver.onReport(metadata, report)
 *         Does not verify DON signatures — unit-test only.
 */
contract MockKeystoneForwarder {
    error ReceiverDoesNotSupportIReceiver(address receiver);

    /// @notice Delivers a report the same way KeystoneForwarder routes to consumers.
    function route(address receiver, bytes calldata metadata, bytes calldata report) external {
        if (!IERC165(receiver).supportsInterface(type(IReceiver).interfaceId)) {
            revert ReceiverDoesNotSupportIReceiver(receiver);
        }
        IReceiver(receiver).onReport(metadata, report);
    }
}
