// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {IERC165} from "@openzeppelin/contracts/utils/introspection/IERC165.sol";

/// @title IReceiver - receives Keystone / CRE reports
/// @notice Implementations must support the IReceiver interface through ERC165.
/// @dev Copied from Chainlink CRE consumer-contract guidance.
interface IReceiver is IERC165 {
    /// @notice Handles incoming Keystone reports.
    /// @dev If this function call reverts, it can be retried with a higher gas limit.
    /// @param metadata Report metadata (workflow identity; 64 bytes from production forwarder).
    /// @param report   ABI-encoded workflow payload.
    function onReport(bytes calldata metadata, bytes calldata report) external;
}
