// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {UserLib} from "./UserLib.sol";

contract Users {
  /// @dev Sentinel value returned by isSubTree when candidate equals root
  uint8 constant SAME_NODE_SENTINEL = 255;

  /// @notice Current highest user ID for incremental assignment
  uint256 nextUserId = 1;

  /// @notice Maps EOA addresses to compact numeric user IDs
  mapping(address => uint256) addressToUserId;

  /// @notice Maps user IDs to User structs
  mapping(uint256 => UserLib.User) users;

  /// @notice Tracks taken positions under each parent to prevent conflicts
  mapping(uint256 => mapping(uint8 => bool)) positionTaken;

  /// @notice Maps user ID to requested wallet address change
  mapping(uint256 => address) changeAddressRequests;

  /// @notice Maps user ID to day to pair index to daily steps count
  mapping(uint256 => mapping(uint256 => uint8[3])) userDailySteps;

  /// @notice Maps user ID to week to total BV for that week
  mapping(uint256 => mapping(uint256 => uint256)) userWeeklyBv;

  /// @notice Modifier to ensure caller is registered user
  /// @param userId The user ID to validate
  modifier onlyRegistered(uint256 userId) {
    if (addressToUserId[msg.sender] != userId || userId == 0) {
      revert UserLib.UserNotRegistered();
    }
    _;
  }

  /**
   * @notice Gets the total number of levels in a path
   * @dev Counts non-zero bytes across all bytes32 elements in the path
   * @param path The path array to measure
   * @return length Total number of path levels
   */
  function _getPathLength(
    bytes32[] storage path
  ) internal view returns (uint256) {
    if (path.length == 0) return 0;

    // Count full bytes32 elements (each contains 32 levels)
    uint256 length = (path.length - 1) * 32;

    // Count bytes in the last bytes32
    bytes32 lastElement = path[path.length - 1];
    for (uint256 i = 0; i < 32; i++) {
      if (uint8(lastElement[i]) != 0) {
        length++;
      } else {
        break;
      }
    }
    return length;
  }

  /**
   * @notice Retrieves a specific byte from the path at given level index
   * @dev Efficiently locates the correct bytes32 and byte position within it
   * @param path The path array to read from
   * @param levelIndex The level index to retrieve (0-based)
   * @return The position value (0-3) at the specified level
   */
  function _getPathByte(
    bytes32[] storage path,
    uint256 levelIndex
  ) internal view returns (uint8) {
    uint256 bytes32Index = levelIndex / 32;
    uint256 byteIndex = levelIndex % 32;

    if (bytes32Index >= path.length) {
      return 0;
    }

    return uint8(path[bytes32Index][byteIndex]);
  }

  /**
   * @notice Registers a new user in the MLM tree
   * @dev First user must have parentId=0 and position=0. All others need valid parent.
   *      Path is computed by copying parent's path and appending new position.
   * @param userAddr The EOA address to register
   * @param parentId The parent user ID (0 for root user only)
   * @param position The position under parent (0-3)
   */
  function _migrateUser(
    address userAddr,
    uint256 parentId,
    uint8 position,
    uint256 bv,
    uint256 withdrawableCommission,
    uint256[4] memory childrenSafeBv,
    uint256[4] memory childrenAggregateBv,
    uint256 lastOrderId
  ) internal {
    if (addressToUserId[userAddr] != 0) {
      revert UserLib.UserAlreadyRegistered();
    }

    if (position > 3) {
      revert UserLib.InvalidPosition();
    }

    // Handle first user (root) registration
    if (nextUserId == 1) {
      if (parentId != 0 || position != 0) {
        revert UserLib.FirstUserMustBeRoot();
      }
    } else {
      // Validate parent exists and position is available
      if (!users[parentId].active) {
        revert UserLib.InvalidParentId();
      }

      if (positionTaken[parentId][position]) {
        revert UserLib.PositionAlreadyTaken();
      }
    }

    // Assign new user ID and create user
    uint256 newUserId = nextUserId++;
    addressToUserId[userAddr] = newUserId;

    UserLib.User storage newUser = users[newUserId];
    newUser.parentId = parentId;
    newUser.userAddress = userAddr;
    newUser.position = position;
    newUser.lastCalculatedOrder = lastOrderId;
    newUser.bv = bv;
    newUser.bvOnBridgeTime = bv;
    newUser.withdrawableCommission = withdrawableCommission;
    newUser.createdAt = block.timestamp;
    newUser.active = true;
    newUser.migrated = true;
    newUser.childrenBv = childrenSafeBv;
    newUser.childrenAggregateBv = childrenAggregateBv;
    newUser.normalNodesBv[0] = childrenSafeBv[0] + childrenSafeBv[1];
    newUser.normalNodesBv[1] = childrenSafeBv[2] + childrenSafeBv[3];

    // Set path based on parent
    // Root user has empty path
    // newUser.path remains empty array
    if (parentId != 0) {
      // Copy parent's path and append new position
      UserLib.User storage parent = users[parentId];
      for (uint256 i = 0; i < parent.path.length; i++) {
        newUser.path.push(parent.path[i]);
      }
      _appendToPath(newUser.path, position);

      // Mark position as taken
      positionTaken[parentId][position] = true;
    }

    emit UserLib.UserMigrated(newUserId, parentId, position, userAddr);
  }

  /**
   * @notice Internal method to get existing user ID or create new user
   * @param userAddr The user's EOA address
   * @param parentAddr The parent user's EOA address
   * @param position The position under parent (0-3)
   * @return userId The user ID (existing or newly created)
   */
  function _getOrCreateUser(
    address userAddr,
    address parentAddr,
    uint8 position,
    uint256 lastOrderId
  ) internal returns (uint256) {
    uint256 userId = addressToUserId[userAddr];

    // If user doesn't exist, create them
    if (userId == 0) {
      // Validate position
      if (position > 3) {
        revert UserLib.InvalidPosition();
      }

      // Validate parent exists (unless this is the first user)
      uint256 parentId = addressToUserId[parentAddr];
      if (nextUserId > 1 && parentId == 0) {
        revert UserLib.InvalidParentAddress();
      }

      // Handle first user (root) registration
      if (nextUserId == 1) {
        if (parentId != 0 || position != 0) {
          revert UserLib.FirstUserMustBeRoot();
        }
      } else {
        // Check if position is already taken
        if (positionTaken[parentId][position]) {
          revert UserLib.PositionAlreadyTaken();
        }

        if (users[parentId].migrated) {
          uint256 migratedParentBv = users[parentId].bv -
            users[parentId].bvOnBridgeTime;
          if (migratedParentBv < 100 ether) {
            if (position != 0 && position != 3) {
              revert UserLib.ParentInsufficientBVForPosition(
                position,
                users[parentId].bv
              );
            }
          } else if (migratedParentBv < 200 ether) {
            if (position != 0 && position != 1 && position != 3) {
              revert UserLib.ParentInsufficientBVForPosition(
                position,
                users[parentId].bv
              );
            }
          }
        } else {
          uint256 parentBv = users[parentId].bv;
          if (parentBv < 200 ether) {
            // Can only refer to positions 0 and 3
            if (position != 0 && position != 3) {
              revert UserLib.ParentInsufficientBVForPosition(
                position,
                parentBv
              );
            }
          } else if (parentBv < 300 ether) {
            // Can refer to positions 0, 1, and 3
            if (position != 0 && position != 1 && position != 3) {
              revert UserLib.ParentInsufficientBVForPosition(
                position,
                parentBv
              );
            }
          }
        }
        // If parentBv >= 300 ether, all positions (0, 1, 2, 3) are allowed
      }

      // Create the user
      userId = nextUserId++;
      addressToUserId[userAddr] = userId;

      UserLib.User storage newUser = users[userId];
      newUser.parentId = parentId;
      newUser.userAddress = userAddr;
      newUser.position = position;
      newUser.lastCalculatedOrder = lastOrderId;
      newUser.bv = 0;
      newUser.withdrawableCommission = 0;
      newUser.createdAt = block.timestamp;
      newUser.active = true;

      // Set path based on parent
      if (parentId != 0) {
        // Copy parent's path and append new position
        UserLib.User storage parent = users[parentId];
        for (uint256 i = 0; i < parent.path.length; i++) {
          newUser.path.push(parent.path[i]);
        }
        _appendToPath(newUser.path, position);

        // Mark position as taken
        positionTaken[parentId][position] = true;
      }

      emit UserLib.UserRegistered(userId, parentId, position, userAddr);
    }

    return userId;
  }

  /**
   * @notice Changes the caller's EOA address to a new address
   * @dev The user ID remains the same, only the address mapping changes.
   *      All tree relationships and commission data are preserved.
   * @param newAddress The new EOA address to associate with the caller's user ID
   */
  function _requestChangeAddress(
    address oldAddress,
    address newAddress
  ) internal {
    // Get the caller's current user ID
    uint256 currentUserId = addressToUserId[oldAddress];
    if (currentUserId == 0) {
      revert UserLib.UserNotRegistered();
    }

    require(
      newAddress != oldAddress,
      "Old and new address cannot be the same."
    );

    changeAddressRequests[currentUserId] = newAddress;
  }

  function _approveChangeAddress(address sender, uint256 userId) internal {
    uint256 parentId = users[userId].parentId;
    uint256 senderId = addressToUserId[sender];
    require(
      parentId == senderId,
      "Only direct parent of the user can approve changing address."
    );

    address newAddress = changeAddressRequests[userId];
    require(
      newAddress != address(0),
      "Provided user id hasn't requested for address change."
    );
    // Check if the new address is already registered
    if (addressToUserId[newAddress] != 0) {
      revert UserLib.AddressAlreadyRegistered();
    }

    // Store old address for event
    address oldAddress = users[userId].userAddress;

    users[userId].userAddress = newAddress;

    // Update the address mappings
    addressToUserId[oldAddress] = 0; // Remove old address mapping
    addressToUserId[newAddress] = userId; // Set new address mapping

    changeAddressRequests[userId] = address(0);

    emit UserLib.AddressChanged(userId, oldAddress, newAddress);
  }

  /**
   * @notice Checks if candidateId is in the subtree of rootId
   * @dev Returns position of direct child through which candidate is reachable.
   *      Uses efficient prefix matching: compares full bytes32 elements first,
   *      then byte-by-byte only for the last partial element. This optimization
   *      significantly reduces gas costs for deep tree structures.
   * @param rootId The root user ID to check against
   * @param candidateId The candidate user ID to test
   * @return inSubTree True if candidate is in root's subtree
   * @return position Direct child position (0-3) or SAME_NODE_SENTINEL if candidate == root
   */
  function _isSubTree(
    uint256 rootId,
    uint256 candidateId
  ) internal view returns (bool inSubTree, uint8 position) {
    if (!users[rootId].active || !users[candidateId].active) {
      return (false, 0);
    }

    if (rootId == candidateId) {
      return (true, SAME_NODE_SENTINEL);
    }

    UserLib.User storage root = users[rootId];
    UserLib.User storage candidate = users[candidateId];

    uint256 rootPathLength = _getPathLength(root.path);
    uint256 candidatePathLength = _getPathLength(candidate.path);

    // Candidate must be deeper than root to be in subtree
    if (candidatePathLength <= rootPathLength) {
      return (false, 0);
    }

    // Check if root's path is a prefix of candidate's path
    // Optimization: Compare full bytes32 elements first, then byte-by-byte for the last partial element

    uint256 rootFullBytes32Count = rootPathLength / 32;
    uint256 rootRemainingBytes = rootPathLength % 32;

    // Compare full bytes32 elements (much more efficient)
    for (uint256 i = 0; i < rootFullBytes32Count; i++) {
      if (root.path[i] != candidate.path[i]) {
        return (false, 0);
      }
    }

    // Compare remaining bytes in the last partial bytes32 element (if any)
    if (rootRemainingBytes > 0) {
      bytes32 rootLastElement = root.path[rootFullBytes32Count];
      bytes32 candidateLastElement = candidate.path[rootFullBytes32Count];

      for (uint256 j = 0; j < rootRemainingBytes; j++) {
        if (uint8(rootLastElement[j]) != uint8(candidateLastElement[j])) {
          return (false, 0);
        }
      }
    }

    // If prefix matches, return the direct child position
    uint8 directChildPos = _getPathByte(candidate.path, rootPathLength);
    return (true, directChildPos - 1);
  }

  /**
   * @notice Internal function to append a position to a path array
   * @dev Writes into the first free byte of the last bytes32, or appends new bytes32 if full
   *      Bytes are packed left-to-right (MSB to LSB) so first position goes in byte 0
   * @param path Storage reference to the path array
   * @param pos Position to append (0-3)
   */
  function _appendToPath(bytes32[] storage path, uint8 pos) internal {
    require(pos <= 3, "Invalid position");

    // If path is empty or last bytes32 is full, add new bytes32
    if (path.length == 0 || _getPathLength(path) % 32 == 0) {
      // Put position in leftmost byte (byte 0) for new bytes32
      path.push(bytes32(uint256(pos + 1)) << (8 * 31));
    } else {
      // Find the last bytes32 and append to it
      uint256 lastIndex = path.length - 1;
      uint256 positionInBytes32 = _getPathLength(path) % 32;

      // Shift position to correct byte position and OR with existing data
      bytes32 currentValue = path[lastIndex];
      bytes32 newByte = bytes32(uint256(pos + 1)) <<
        (8 * (31 - positionInBytes32));
      path[lastIndex] = currentValue | newByte;
    }
  }

  function _addUserBv(
    uint256 userId,
    uint256 weekNumber,
    uint256 amount
  ) internal onlyRegistered(userId) {
    users[userId].bv += amount;
    userWeeklyBv[userId][weekNumber] += amount;
  }

  function _getUserPairByIndex(
    uint256 userId,
    uint8 pair
  ) internal view onlyRegistered(userId) returns (uint256, uint256) {
    UserLib.User storage user = users[userId];
    // Get the appropriate BV pair
    if (pair == 0) {
      // Pair 0: childrenBv[0] vs childrenBv[1]
      return (user.childrenBv[0], user.childrenBv[1]);
    } else if (pair == 1) {
      // Pair 1: childrenBv[2] vs childrenBv[3]
      return (user.childrenBv[2], user.childrenBv[3]);
    } else {
      // Pair 2: normalNodesBv[0] vs normalNodesBv[1]
      return (user.normalNodesBv[0], user.normalNodesBv[1]);
    }
  }

  function _setUserPairByIndex(
    uint256 userId,
    uint256 leftBv,
    uint256 rightBv,
    uint8 pair
  ) internal onlyRegistered(userId) {
    UserLib.User storage user = users[userId];

    if (pair == 0) {
      user.childrenBv[0] = leftBv;
      user.childrenBv[1] = rightBv;
    } else if (pair == 1) {
      user.childrenBv[2] = leftBv;
      user.childrenBv[3] = rightBv;
    } else {
      user.normalNodesBv[0] = leftBv;
      user.normalNodesBv[1] = rightBv;
    }
  }

  function _getUserById(
    uint256 userId
  ) internal view onlyRegistered(userId) returns (UserLib.User storage) {
    UserLib.User storage user = users[userId];

    return user;
  }

  function _getUserIdByAddress(
    address userAddress
  ) internal view returns (uint256) {
    return addressToUserId[userAddress];
  }

  function _userExistsByAddress(
    address userAddress
  ) internal view returns (bool) {
    return addressToUserId[userAddress] != 0;
  }

  function _getUserByAddress(
    address userAddress
  ) internal view returns (UserLib.User storage) {
    uint256 userId = addressToUserId[userAddress];
    if (userId == 0) {
      revert UserLib.UserNotRegistered();
    }

    return users[userId];
  }

  function _getUserDailySteps(
    uint256 userId,
    uint256 dayNumber,
    uint8 pair
  ) internal view returns (uint8) {
    return userDailySteps[userId][dayNumber][pair];
  }

  function _getUserWeeklyBv(
    uint256 userId,
    uint256 weekNumber
  ) internal view returns (uint256) {
    return userWeeklyBv[userId][weekNumber];
  }

  function _setUserDailySteps(
    uint256 userId,
    uint256 dayNumber,
    uint8 pair,
    uint8 value
  ) internal {
    userDailySteps[userId][dayNumber][pair] = value;
  }
}
