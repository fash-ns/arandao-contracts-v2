// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

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
contract MLMTree is ReentrancyGuard, Ownable {
    /// @dev Maximum orders to process in single calculateOrders call to prevent OOG
    uint256 public constant MAX_PROCESS_LIMIT = 2000;
    
    /// @dev Sentinel value returned by isSubTree when candidate equals root
    uint8 public constant SAME_NODE_SENTINEL = 255;

    /// @notice User data structure containing tree position and commission tracking
    struct User {
        uint32 parentId;                    // Parent user ID (0 for root)
        uint8 position;                     // Position under parent (0-3)
        bytes32[] path;                     // Encoded path from root to user
        uint256 lastCalculatedOrder;       // Last processed order ID for this user
        uint256[4] childrenBv;             // Accumulated BV for each direct child position
        uint256 createdAt;                 // Block timestamp of registration
        bool active;                       // Whether user is active
    }

    /// @notice Order data structure for tracking purchases
    struct Order {
        uint32 buyerId;                     // User ID who made the purchase
        uint256 amount;                     // Purchase amount/BV
        uint256 timestamp;                  // Block timestamp of order
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
    
    /// @notice Current highest order ID
    uint256 public lastOrderId;
    
    /// @notice Current highest user ID for incremental assignment
    uint32 public nextUserId = 1;

    // Events
    /// @notice Emitted when a new user is registered
    /// @param userId The assigned user ID
    /// @param parentId The parent user ID
    /// @param position The position under parent (0-3)
    /// @param userAddr The user's EOA address
    event UserRegistered(uint32 indexed userId, uint32 indexed parentId, uint8 position, address indexed userAddr);
    
    /// @notice Emitted when a new order is created
    /// @param orderId The assigned order ID
    /// @param buyerId The user ID who made the purchase
    /// @param amount The purchase amount
    event OrderCreated(uint256 indexed orderId, uint32 indexed buyerId, uint256 amount);
    
    /// @notice Emitted when orders are processed for commission calculation
    /// @param userId The user ID for whom orders were calculated
    /// @param processed Number of orders processed in this call
    /// @param lastCalculatedOrder New value of lastCalculatedOrder for this user
    event OrdersCalculated(uint32 indexed userId, uint256 processed, uint256 lastCalculatedOrder);

    // Custom errors
    error InvalidParentId();
    error InvalidPosition();
    error PositionAlreadyTaken();
    error UserAlreadyRegistered();
    error UserNotRegistered();
    error UnauthorizedCaller();
    error MaxProcessLimitExceeded();
    error FirstUserMustBeRoot();

    /// @notice Modifier to ensure caller is registered user
    /// @param userId The user ID to validate
    modifier onlyRegistered(uint32 userId) {
        if (addressToId[msg.sender] != userId || userId == 0) {
            revert UnauthorizedCaller();
        }
        _;
    }

    constructor() Ownable(msg.sender) {}

    /**
     * @notice Registers a new user in the MLM tree
     * @dev First user must have parentId=0 and position=0. All others need valid parent.
     *      Path is computed by copying parent's path and appending new position.
     * @param userAddr The EOA address to register
     * @param parentId The parent user ID (0 for root user only)
     * @param position The position under parent (0-3)
     */
    function registerUser(address userAddr, uint32 parentId, uint8 position) external {
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
     * @notice Creates a new order for commission calculation
     * @dev Only the buyer's linked address can create orders for their user ID
     * @param buyerId The user ID making the purchase
     * @param amount The purchase amount/BV
     */
    function createOrder(uint32 buyerId, uint256 amount) external onlyRegistered(buyerId) {
        uint256 newOrderId = ++lastOrderId;
        
        orders[newOrderId] = Order({
            buyerId: buyerId,
            amount: amount,
            timestamp: block.timestamp
        });

        emit OrderCreated(newOrderId, buyerId, amount);
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
    function calculateOrders(uint32 callerId, uint256 maxProcess) 
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

        // Local storage for batch updating childrenBv
        uint256[4] memory bvUpdates;

        while (cur <= end && processed < maxProcess) {
            Order memory order = orders[cur];
            
            (bool inSubTree, uint8 childPosition) = isSubTree(callerId, order.buyerId);
            
            if (inSubTree && childPosition != SAME_NODE_SENTINEL) {
                // Accumulate BV update for the direct child position
                bvUpdates[childPosition] += order.amount;
            }
            
            cur++;
            processed++;
        }

        // Batch update storage with accumulated values
        for (uint8 i = 0; i < 4; i++) {
            if (bvUpdates[i] > 0) {
                users[callerId].childrenBv[i] += bvUpdates[i];
            }
        }

        newLastCalculatedOrder = cur - 1;
        users[callerId].lastCalculatedOrder = newLastCalculatedOrder;

        emit OrdersCalculated(callerId, processed, newLastCalculatedOrder);
    }

    /**
     * @notice Checks if candidateId is in the subtree of rootId
     * @dev Returns position of direct child through which candidate is reachable.
     *      Uses efficient prefix matching on encoded paths.
     * @param rootId The root user ID to check against
     * @param candidateId The candidate user ID to test
     * @return inSubTree True if candidate is in root's subtree
     * @return position Direct child position (0-3) or SAME_NODE_SENTINEL if candidate == root
     */
    function isSubTree(uint32 rootId, uint32 candidateId) 
        public 
        view 
        returns (bool inSubTree, uint8 position) 
    {
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
        for (uint256 i = 0; i < rootPathLength; i++) {
            if (_getPathByte(root.path, i) != _getPathByte(candidate.path, i)) {
                return (false, 0);
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
            bytes32 newByte = bytes32(uint256(pos + 1)) << (8 * (31 - positionInBytes32));
            path[lastIndex] = currentValue | newByte;
        }
    }

    /**
     * @notice Gets the total number of levels in a path
     * @dev Counts non-zero bytes across all bytes32 elements in the path
     * @param path The path array to measure
     * @return length Total number of path levels
     */
    function _getPathLength(bytes32[] storage path) internal view returns (uint256 length) {
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
    function _getPathByte(bytes32[] storage path, uint256 levelIndex) 
        internal 
        view 
        returns (uint8) 
    {
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
    function getUserByAddress(address userAddr) external view returns (User memory) {
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
}
