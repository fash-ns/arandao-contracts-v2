// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

/**
 * @title MLMTree - Multi-Level Marketing Binary Tree Contract
 * @notice Implements a secure, gas-conscious MLM tree structure with on-chain order bookkeeping
 * @dev Each node can have up to 4 children (positions 0-3). Path encoding uses bytes32 arrays
 *      where each byte represents a position (0x00-0x03). Supports efficient subtree calculations
 *      and commission tracking via lastCalculatedOrder mechanism.
 *
 * Path Encoding:
 * - Each bytes32 contains up to 32 path levels
 * - Each byte holds values 0x00, 0x01, 0x02, 0x03 representing positions 0-3
 * - When path exceeds 32 levels, new bytes32 is appended to array
 *
 * isSubTree Semantics:
 * - Returns (true, position) if candidate is in subtree via direct child at position
 * - Returns (true, 255) when candidate == root (sentinel value for same node)
 * - Returns (false, 0) if not in subtree
 */
contract MLMTree is ReentrancyGuard {
  /// @dev Maximum orders to process in single calculateOrders call to prevent OOG
  uint256 public constant MAX_PROCESS_LIMIT = 2000;

  /// @dev Sentinel value returned by isSubTree when candidate equals root
  uint8 public constant SAME_NODE_SENTINEL = 255;

  /// @notice Amount data structure containing both SV and BV values
  struct Amount {
    uint256 sv; // Sales Volume
    uint256 bv; // Business Volume
  }

  /// @notice User data structure containing tree position and commission tracking
  struct User {
    uint32 parentId; // Parent user ID (0 for root)
    uint8 position; // Position under parent (0-3)
    bytes32[] path; // Encoded path from root to user
    uint256 lastCalculatedOrder; // Last processed order ID for this user
    uint256[4] childrenBv; // Accumulated BV for each direct childs of normal nodes position
    uint256[2] normalNodesBv; // Accumulated BV for normal nodes
    uint256 bv; // User's total business volume
    uint256 withdrawableCommission; // User's earned commission available for withdrawal
    uint256 createdAt; // Block timestamp of registration
    bool active; // Whether user is active
  }

  /// @notice Order data structure for tracking purchases
  struct Order {
    uint32 buyerId; // User ID who made the purchase
    uint32 sellerId; // Seller ID who made the sale
    uint256 sv; // Sales value
    uint256 bv; // Business value
    uint256 createdAt; // Block timestamp of order
  }

  /// @notice Seller data structure for tracking sales and commissions
  struct Seller {
    uint256 bv; // Total business volume generated
    uint256 withdrawnBv; // BV that has been withdrawn
    uint256 createdAt; // Block timestamp of registration
    bool active; // Whether seller is active
  }

  // Storage mappings
  /// @notice Maps EOA addresses to compact numeric user IDs
  mapping(address => uint32) public addressToId;

  /// @notice Maps user IDs to User structs
  mapping(uint32 => User) public users;

  /// @notice Tracks taken positions under each parent to prevent conflicts
  mapping(uint32 => mapping(uint8 => bool)) public positionTaken;

  /// @notice Maps order IDs to Order structs
  mapping(uint256 => Order) public orders;

  /// @notice Maps seller addresses to compact numeric seller IDs
  mapping(address => uint32) public addressToSellerId;

  /// @notice Maps seller IDs to Seller structs
  mapping(uint32 => Seller) public sellers;

  /// @notice Current highest order ID
  uint256 public lastOrderId;

  /// @notice Current highest user ID for incremental assignment
  uint32 public nextUserId = 1;

  /// @notice Current highest seller ID for incremental assignment
  uint32 public nextSellerId = 1;

  /// @notice Maps user ID to day to pair index to daily steps count
  mapping(uint32 => mapping(uint256 => uint256[3])) public userDailySteps;

  /// @notice Maps day to total global steps for that day
  mapping(uint256 => uint256) public globalDailySteps;

  /// @notice Maps day to flush-out counter for that day
  mapping(uint256 => uint256) public globalDailyFlushOuts;

  // Events
  /// @notice Emitted when a new user is registered
  /// @param userId The assigned user ID
  /// @param parentId The parent user ID
  /// @param position The position under parent (0-3)
  /// @param userAddr The user's EOA address
  event UserRegistered(
    uint32 indexed userId,
    uint32 indexed parentId,
    uint8 position,
    address indexed userAddr
  );

  /// @notice Emitted when a new order is created
  /// @param orderId The assigned order ID
  /// @param buyerId The user ID who made the purchase
  /// @param amount The purchase amount
  event OrderCreated(
    uint256 indexed orderId,
    uint32 indexed buyerId,
    uint256 amount
  );

  /// @notice Emitted when orders are processed for commission calculation
  /// @param userId The user ID for whom orders were calculated
  /// @param processed Number of orders processed in this call
  /// @param lastCalculatedOrder New value of lastCalculatedOrder for this user
  event OrdersCalculated(
    uint32 indexed userId,
    uint256 processed,
    uint256 lastCalculatedOrder
  );

  /// @notice Emitted when a user changes their EOA address
  /// @param userId The user ID that changed their address
  /// @param oldAddress The previous EOA address
  /// @param newAddress The new EOA address
  event AddressChanged(
    uint32 indexed userId,
    address indexed oldAddress,
    address indexed newAddress
  );

  /// @notice Emitted when a new seller is registered
  /// @param sellerId The assigned seller ID
  /// @param sellerAddr The seller's EOA address
  event SellerRegistered(uint32 indexed sellerId, address indexed sellerAddr);

  /// @notice Emitted when daily commission is calculated for a user
  /// @param userId The user ID for whom commission was calculated
  /// @param day The day (timestamp / 86400) for the calculation
  /// @param totalCommission The total commission amount earned
  /// @param pairProcessed The number of pairs that had steps processed
  event DailyCommissionCalculated(
    uint32 indexed userId,
    uint256 indexed day,
    uint256 totalCommission,
    uint8 pairProcessed,
    uint256 steps
  );

  event UserFlushedOut(uint256 indexed userId, uint256 indexed day);

  /// @notice Emitted when a user withdraws commission
  /// @param userId The user ID who withdrew
  /// @param amount The amount withdrawn
  event CommissionWithdrawn(uint32 indexed userId, uint256 amount);

  // Custom errors
  error InvalidParentId();
  error InvalidPosition();
  error PositionAlreadyTaken();
  error UserAlreadyRegistered();
  error UserNotRegistered();
  error UnauthorizedCaller();
  error MaxProcessLimitExceeded();
  error FirstUserMustBeRoot();
  error AddressAlreadyRegistered();
  error SellerNotRegistered();
  error InsufficientBVForNewUser();
  error InvalidParentAddress();
  error ParentInsufficientBVForPosition(uint8 position, uint256 parentBv);

  /// @notice Modifier to ensure caller is registered user
  /// @param userId The user ID to validate
  modifier onlyRegistered(uint32 userId) {
    if (addressToId[msg.sender] != userId || userId == 0) {
      revert UnauthorizedCaller();
    }
    _;
  }

  constructor() {}

  /**
   * @notice Registers a new user in the MLM tree
   * @dev First user must have parentId=0 and position=0. All others need valid parent.
   *      Path is computed by copying parent's path and appending new position.
   * @param userAddr The EOA address to register
   * @param parentId The parent user ID (0 for root user only)
   * @param position The position under parent (0-3)
   */
  function registerUser(
    address userAddr,
    uint32 parentId,
    uint8 position
  ) external {
    if (addressToId[userAddr] != 0) {
      revert UserAlreadyRegistered();
    }

    if (position > 3) {
      revert InvalidPosition();
    }

    // Handle first user (root) registration
    if (nextUserId == 1) {
      if (parentId != 0 || position != 0) {
        revert FirstUserMustBeRoot();
      }
    } else {
      // Validate parent exists and position is available
      if (parentId == 0 || !users[parentId].active) {
        revert InvalidParentId();
      }

      if (positionTaken[parentId][position]) {
        revert PositionAlreadyTaken();
      }
    }

    // Assign new user ID and create user
    uint32 newUserId = nextUserId++;
    addressToId[userAddr] = newUserId;

    User storage newUser = users[newUserId];
    newUser.parentId = parentId;
    newUser.position = position;
    newUser.lastCalculatedOrder = lastOrderId; // Start from current order
    newUser.bv = 0; // Initialize BV to 0
    newUser.withdrawableCommission = 0; // Initialize commission to 0
    newUser.createdAt = block.timestamp;
    newUser.active = true;

    // Set path based on parent
    if (parentId == 0) {
      // Root user has empty path
      // newUser.path remains empty array
    } else {
      // Copy parent's path and append new position
      User storage parent = users[parentId];
      for (uint256 i = 0; i < parent.path.length; i++) {
        newUser.path.push(parent.path[i]);
      }
      _appendToPath(newUser.path, position);
    }

    // Mark position as taken
    if (parentId != 0) {
      positionTaken[parentId][position] = true;
    }

    emit UserRegistered(newUserId, parentId, position, userAddr);
  }

  /**
   * @notice Internal method to get existing seller ID or create new seller
   * @param sellerAddr The seller's EOA address
   * @return sellerId The seller ID (existing or newly created)
   */
  function _getOrCreateSeller(
    address sellerAddr
  ) internal returns (uint32 sellerId) {
    sellerId = addressToSellerId[sellerAddr];

    // If seller doesn't exist, create them
    if (sellerId == 0) {
      sellerId = nextSellerId++;
      addressToSellerId[sellerAddr] = sellerId;

      sellers[sellerId] = Seller({
        bv: 0,
        withdrawnBv: 0,
        createdAt: block.timestamp,
        active: true
      });

      emit SellerRegistered(sellerId, sellerAddr);
    }

    return sellerId;
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
    uint8 position
  ) internal returns (uint32 userId) {
    userId = addressToId[userAddr];

    // If user doesn't exist, create them
    if (userId == 0) {
      // Validate position
      if (position > 3) {
        revert InvalidPosition();
      }

      // Validate parent exists (unless this is the first user)
      uint32 parentId = addressToId[parentAddr];
      if (nextUserId > 1 && parentId == 0) {
        revert InvalidParentAddress();
      }

      // Handle first user (root) registration
      if (nextUserId == 1) {
        if (parentId != 0 || position != 0) {
          revert FirstUserMustBeRoot();
        }
      } else {
        // Check if position is already taken
        if (positionTaken[parentId][position]) {
          revert PositionAlreadyTaken();
        }

        // Check if parent has sufficient BV for the requested position
        uint256 parentBv = users[parentId].bv;
        if (parentBv < 200 ether) {
          // Can only refer to positions 0 and 3
          if (position != 0 && position != 3) {
            revert ParentInsufficientBVForPosition(position, parentBv);
          }
        } else if (parentBv >= 200 ether && parentBv < 300 ether) {
          // Can refer to positions 0, 1, and 3
          if (position != 0 && position != 1 && position != 3) {
            revert ParentInsufficientBVForPosition(position, parentBv);
          }
        }
        // If parentBv >= 300 ether, all positions (0, 1, 2, 3) are allowed
      }

      // Create the user
      userId = nextUserId++;
      addressToId[userAddr] = userId;

      User storage newUser = users[userId];
      newUser.parentId = parentId;
      newUser.position = position;
      newUser.lastCalculatedOrder = lastOrderId;
      newUser.bv = 0;
      newUser.withdrawableCommission = 0;
      newUser.createdAt = block.timestamp;
      newUser.active = true;

      // Set path based on parent
      if (parentId != 0) {
        // Copy parent's path and append new position
        User storage parent = users[parentId];
        for (uint256 i = 0; i < parent.path.length; i++) {
          newUser.path.push(parent.path[i]);
        }
        _appendToPath(newUser.path, position);

        // Mark position as taken
        positionTaken[parentId][position] = true;
      }

      emit UserRegistered(userId, parentId, position, userAddr);
    }

    return userId;
  }

  /**
   * @notice Creates new orders for commission calculation
   * @dev Buyer and seller will be automatically registered if they don't exist.
   *      For new users, total BV must be greater than 100 ether.
   * @param buyerAddress The buyer's EOA address
   * @param parentAddress The parent's EOA address (for user creation)
   * @param position The position under parent (0-3, for user creation)
   * @param sellerAddress The seller's EOA address
   * @param amounts Array of Amount structs containing SV and BV values
   */
  function createOrder(
    address buyerAddress,
    address parentAddress,
    uint8 position,
    address sellerAddress,
    Amount[] calldata amounts
  ) external {
    require(amounts.length > 0, "At least one amount required");

    // Check if user exists
    uint32 buyerId = addressToId[buyerAddress];
    bool isNewUser = (buyerId == 0);

    // Calculate total BV for validation
    uint256 totalBv = 0;
    for (uint256 i = 0; i < amounts.length; i++) {
      totalBv += amounts[i].bv;
    }

    // If new user, validate minimum BV requirement
    if (isNewUser) {
      if (totalBv < 100 ether) revert InsufficientBVForNewUser();
    }

    // Get or create user and seller
    buyerId = _getOrCreateUser(buyerAddress, parentAddress, position);
    uint32 sellerId = _getOrCreateSeller(sellerAddress);

    // Calculate BV to add (0.8 * order BV)
    uint256 bvToAdd = (totalBv * 80) / 100; // 0.8 * totalBV

    // Process each amount and create orders
    for (uint256 i = 0; i < amounts.length; i++) {
      uint256 newOrderId = ++lastOrderId;

      orders[newOrderId] = Order({
        buyerId: buyerId,
        sellerId: sellerId,
        sv: amounts[i].sv,
        bv: amounts[i].bv,
        createdAt: block.timestamp
      });

      emit OrderCreated(newOrderId, buyerId, amounts[i].bv);
    }

    // Update seller's BV (0.8 * total order BV)
    sellers[sellerId].bv += bvToAdd;

    // Update user's BV (0.8 * total order BV)
    users[buyerId].bv += bvToAdd;
  }

  /**
   * @notice Changes the caller's EOA address to a new address
   * @dev The user ID remains the same, only the address mapping changes.
   *      All tree relationships and commission data are preserved.
   * @param newAddress The new EOA address to associate with the caller's user ID
   */
  function changeAddress(address newAddress) external {
    // Get the caller's current user ID
    uint32 currentUserId = addressToId[msg.sender];
    if (currentUserId == 0) {
      revert UserNotRegistered();
    }

    // Check if the new address is already registered
    if (addressToId[newAddress] != 0) {
      revert AddressAlreadyRegistered();
    }

    // Store old address for event
    address oldAddress = msg.sender;

    // Update the address mappings
    addressToId[oldAddress] = 0; // Remove old address mapping
    addressToId[newAddress] = currentUserId; // Set new address mapping

    emit AddressChanged(currentUserId, oldAddress, newAddress);
  }

  /**
   * @notice Processes orders for commission calculation with gas limit protection
   * @dev Iterates through orders starting from lastCalculatedOrder + 1, updating
   *      childrenBv for direct children whose subtrees contain the buyers
   * @param callerId The user ID to calculate commissions for
   * @param maxProcess Maximum orders to process (capped at MAX_PROCESS_LIMIT)
   * @return processed Number of orders processed
   * @return newLastCalculatedOrder Updated lastCalculatedOrder value
   */
  function calculateOrders(
    uint32 callerId,
    uint256 maxProcess
  )
    external
    nonReentrant
    returns (uint256 processed, uint256 newLastCalculatedOrder)
  {
    if (maxProcess > MAX_PROCESS_LIMIT) {
      revert MaxProcessLimitExceeded();
    }

    if (!users[callerId].active) {
      revert UserNotRegistered();
    }

    uint256 cur = users[callerId].lastCalculatedOrder + 1;
    uint256 end = lastOrderId;
    processed = 0;

    uint256 lastCalculatedOrderDate = orders[
      users[callerId].lastCalculatedOrder
    ].createdAt;

    while (cur <= end && processed < maxProcess) {
      Order memory order = orders[cur];

      if (getDayOfTs(lastCalculatedOrderDate) < getDayOfTs(order.createdAt)) {
        calculateDailyCommission(callerId, getDayOfTs(lastCalculatedOrderDate));
      }

      (bool inSubTree, uint8 childPosition) = isSubTree(
        callerId,
        order.buyerId
      );

      if (inSubTree && childPosition != SAME_NODE_SENTINEL) {
        // Accumulate BV update for the direct child position
        users[callerId].childrenBv[childPosition] += (order.bv * 80) / 100;
        users[callerId].normalNodesBv[childPosition / 2] +=
          (order.bv * 80) / 100;
        //TODO: Should be the total BV or 0.8 BV?
      }

      cur++;
      processed++;
      lastCalculatedOrderDate = order.createdAt;
    }

    newLastCalculatedOrder = cur - 1;
    users[callerId].lastCalculatedOrder = newLastCalculatedOrder;

    emit OrdersCalculated(callerId, processed, newLastCalculatedOrder);
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
  function isSubTree(
    uint32 rootId,
    uint32 candidateId
  ) public view returns (bool inSubTree, uint8 position) {
    if (!users[rootId].active || !users[candidateId].active) {
      return (false, 0);
    }

    if (rootId == candidateId) {
      return (true, SAME_NODE_SENTINEL);
    }

    User storage root = users[rootId];
    User storage candidate = users[candidateId];

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

  /**
   * @notice Gets the total number of levels in a path
   * @dev Counts non-zero bytes across all bytes32 elements in the path
   * @param path The path array to measure
   * @return length Total number of path levels
   */
  function _getPathLength(
    bytes32[] storage path
  ) internal view returns (uint256 length) {
    if (path.length == 0) return 0;

    // Count full bytes32 elements (each contains 32 levels)
    length = (path.length - 1) * 32;

    // Count bytes in the last bytes32
    bytes32 lastElement = path[path.length - 1];
    for (uint256 i = 0; i < 32; i++) {
      if (uint8(lastElement[i]) != 0) {
        length++;
      } else {
        break;
      }
    }
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
   * @notice Gets user information by address
   * @param userAddr The user's EOA address
   * @return User struct data
   */
  function getUserByAddress(
    address userAddr
  ) external view returns (User memory) {
    uint32 userId = addressToId[userAddr];
    require(userId != 0, "User not found");
    return users[userId];
  }

  /**
   * @notice Gets the current path length for a user
   * @param userId The user ID to query
   * @return Path length (number of levels from root)
   */
  function getUserPathLength(uint32 userId) external view returns (uint256) {
    require(users[userId].active, "User not found");
    return _getPathLength(users[userId].path);
  }

  function getUserPath(uint32 userId) external view returns (bytes32[] memory) {
    require(users[userId].active, "User not found");
    return users[userId].path;
  }

  /**
   * @notice Gets remaining orders to be processed for a user
   * @param userId The user ID to query
   * @return Number of orders remaining to be processed
   */
  function getRemainingOrders(uint32 userId) external view returns (uint256) {
    require(users[userId].active, "User not found");
    uint256 lastCalculated = users[userId].lastCalculatedOrder;
    if (lastOrderId > lastCalculated) {
      return lastOrderId - lastCalculated;
    }
    return 0;
  }

  /**
   * @notice Gets seller information by address
   * @param sellerAddr The seller's EOA address
   * @return Seller struct data
   */
  function getSellerByAddress(
    address sellerAddr
  ) external view returns (Seller memory) {
    uint32 sellerId = addressToSellerId[sellerAddr];
    require(sellerId != 0, "Seller not found");
    return sellers[sellerId];
  }

  /**
   * @notice Gets available BV for withdrawal for a seller
   * @param sellerId The seller ID to query
   * @return Available BV amount (total BV - withdrawn BV)
   */
  function getAvailableBV(uint32 sellerId) external view returns (uint256) {
    require(sellers[sellerId].active, "Seller not found");
    return sellers[sellerId].bv - sellers[sellerId].withdrawnBv;
  }

  /**
   * @notice Allows a seller to withdraw their available BV
   * @param sellerId The seller ID requesting withdrawal
   * @param amount The amount to withdraw
   */
  function withdrawBV(uint32 sellerId, uint256 amount) external {
    uint32 callerSellerId = addressToSellerId[msg.sender];
    if (callerSellerId != sellerId || sellerId == 0) {
      revert UnauthorizedCaller();
    }

    if (!sellers[sellerId].active) {
      revert SellerNotRegistered();
    }

    uint256 availableBV = sellers[sellerId].bv - sellers[sellerId].withdrawnBv;
    require(amount <= availableBV, "Insufficient available BV");

    sellers[sellerId].withdrawnBv += amount;

    // Here you would typically transfer tokens or handle the withdrawal
    // For now, we just update the internal accounting
  }

  function getUserPairByIndex(
    User storage user,
    uint8 pair
  ) internal view returns (uint256, uint256) {
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

  function setUserPairByIndex(
    User storage user,
    uint256 leftBv,
    uint256 rightBv,
    uint8 pair
  ) internal {
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

  /**
   * @notice Calculates daily commission for a specific user based on their BV pairs
   * @dev Processes 3 pairs: childrenBv[0-1], childrenBv[2-3], and normalNodesBv[0-1]
   *      Each pair can have max 6 steps per day. At 6 steps, both sides are flushed to 0.
   * @param userId The user ID to calculate commission for
   */
  function calculateDailyCommission(
    uint32 userId,
    uint256 lastOrderTimestamp
  ) internal {
    require(users[userId].active, "User not found");

    User storage user = users[userId];
    uint256 dayNumber = getDayOfTs(lastOrderTimestamp);
    uint256 totalCommissionEarned = 0;

    // Process 3 pairs
    for (uint8 pairIndex = 0; pairIndex < 3; pairIndex++) {
      uint256 leftBv;
      uint256 rightBv;

      (leftBv, rightBv) = getUserPairByIndex(user, pairIndex);

      uint256 currentSteps = userDailySteps[userId][dayNumber][pairIndex];

      // Process steps while both sides >= 500 ether and steps < 6
      while (leftBv >= 500 ether && rightBv >= 500 ether && currentSteps < 6) {
        // Subtract 500 ether from both sides
        leftBv -= 500 ether;
        rightBv -= 500 ether;

        // Add 60 ether commission
        totalCommissionEarned += 60 ether;

        // Increment counters
        currentSteps++;
        globalDailySteps[dayNumber]++;
      }

      setUserPairByIndex(user, leftBv, rightBv, pairIndex);

      // Update daily steps for this pair
      userDailySteps[userId][dayNumber][pairIndex] = currentSteps;

      // Check for flush-out (6 steps reached)
      if (currentSteps == 6) {
        // Set both sides to 0 (discard excess BV)
        setUserPairByIndex(user, 0, 0, pairIndex);
        globalDailyFlushOuts[dayNumber]++;

        emit UserFlushedOut(userId, dayNumber);
      }

      emit DailyCommissionCalculated(
        userId,
        dayNumber,
        totalCommissionEarned,
        pairIndex,
        currentSteps
      );
    }

    // Add earned commission to user's withdrawable balance
    user.withdrawableCommission += totalCommissionEarned;
  }

  /**
   * @notice Allows a user to withdraw their accumulated commission
   * @param amount The amount to withdraw
   */
  function withdrawCommission(uint256 amount) external nonReentrant {
    uint32 userId = addressToId[msg.sender];
    require(userId != 0, "User not registered");

    User storage user = users[userId];
    require(user.active, "User not active");
    require(
      amount <= user.withdrawableCommission,
      "Insufficient commission balance"
    );

    user.withdrawableCommission -= amount;

    // Here you would typically transfer tokens or handle the withdrawal
    // For now, we just update the internal accounting

    emit CommissionWithdrawn(userId, amount);
  }

  /**
   * @notice Gets the current day number (timestamp / 86400)
   * @return The current day
   */
  function getDayOfTs(uint256 timestamp) public pure returns (uint256) {
    return timestamp / 86400;
  }

  /**
   * @notice Gets user's daily steps for a specific day and pair
   * @param userId The user ID
   * @param day The day to query
   * @param pairIndex The pair index (0-2)
   * @return The number of steps for that day and pair
   */
  function getUserDailySteps(
    uint32 userId,
    uint256 day,
    uint8 pairIndex
  ) external view returns (uint256) {
    require(pairIndex < 3, "Invalid pair index");
    return userDailySteps[userId][day][pairIndex];
  }

  /**
   * @notice Gets user's withdrawable commission
   * @param userId The user ID
   * @return The withdrawable commission amount
   */
  function getUserWithdrawableCommission(
    uint32 userId
  ) external view returns (uint256) {
    require(users[userId].active, "User not found");
    return users[userId].withdrawableCommission;
  }

  /**
   * @notice Gets global statistics for a specific day
   * @param day The day to query
   * @return totalSteps The total steps processed that day
   * @return flushOuts The total flush-outs that day
   */
  function getGlobalDailyStats(
    uint256 day
  ) external view returns (uint256 totalSteps, uint256 flushOuts) {
    return (globalDailySteps[day], globalDailyFlushOuts[day]);
  }

  /**
   * @notice Gets user's children BV information
   * @param userId The user ID to query
   * @return childrenBv The user's children BV array
   */
  function getUserChildrenBv(
    uint32 userId
  ) external view returns (uint256[4] memory childrenBv) {
    require(users[userId].active, "User not found");
    return users[userId].childrenBv;
  }

  /**
   * @notice Gets user's normal nodes BV information
   * @param userId The user ID to query
   * @return normalNodesBv The user's normal nodes BV array
   */
  function getUserNormalNodesBv(
    uint32 userId
  ) external view returns (uint256[2] memory normalNodesBv) {
    require(users[userId].active, "User not found");
    return users[userId].normalNodesBv;
  }
}
