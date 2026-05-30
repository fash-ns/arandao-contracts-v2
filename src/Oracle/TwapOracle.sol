// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

// ─── Minimal interfaces ─────────────────────────────────────────────────────────

interface IUniswapV2Pair {
    function token0() external view returns (address);
    function token1() external view returns (address);
    function getReserves() external view returns (uint112 reserve0, uint112 reserve1, uint32 blockTimestampLast);
    function price0CumulativeLast() external view returns (uint256);
    function price1CumulativeLast() external view returns (uint256);
}

interface IERC20Decimals {
    function decimals() external view returns (uint8);
}

/**
 * @title TwapOracle
 * @notice Single-token Uniswap V2 TWAP price feed with a two-phase design.
 *
 * Phase 1 — Fixed price
 * ─────────────────────
 *  getPrice() returns FIXED_PRICE until the lpActivator activates TWAP mode.
 *  This lets the protocol bootstrap with a known seed price before a live
 *  Uniswap V2 pool exists.
 *
 * Phase 2 — Live TWAP  (activated exactly once by the lpActivator role)
 * ───────────────────────────────────────────────────────────────────────
 *  lpActivator calls activateTwap(pair, keeper) once, supplying the address of
 *  the Uniswap V2 token/quoteToken pair and the keeper that will push updates.
 *
 *    • PERIOD (8 h) must elapse since activation before the first update() is
 *      accepted, establishing a full TWAP window.
 *    • Until hasBeenUpdated == true, getPrice() still returns FIXED_PRICE —
 *      there is never a zero-price window.
 *    • getPrice() returns the TWAP price of `token` in `quoteToken` base units.
 *      Example: 1 ARC at 300 USDT → 300_000_000 (USDT has 6 decimals).
 *
 * TWAP math
 * ─────────
 *  Mirrors UniswapV2OracleLibrary in Solidity ^0.8.30.  UQ112x112 arithmetic
 *  is used throughout; cumulative-price subtractions are unchecked because
 *  Uniswap V2 intentionally allows those uint256 accumulators to overflow.
 */
contract TwapOracle {
    // ─── Constants ──────────────────────────────────────────────────────────────

    /// @notice Minimum time between successive keeper updates.
    uint256 public constant PERIOD = 8 hours;

    // ─── Immutables ─────────────────────────────────────────────────────────────

    /// @notice Token whose price is tracked (e.g. ARC, 18 decimals).
    address public immutable token;

    /// @notice Token in which the price is expressed (e.g. USDT, 6 decimals).
    address public immutable quoteToken;

    /// @notice Address authorised to call activateTwap exactly once.
    address public immutable lpActivator;

    /// @notice Phase-1 seed price, in quoteToken base units (e.g. 300_000_000 for 300 USDT).
    uint256 public immutable FIXED_PRICE;

    // ─── Phase 2 state ──────────────────────────────────────────────────────────

    /// @notice Permanently true after activateTwap is called.
    bool public twapActive;

    /// @notice True once the first successful update() snapshot has been committed.
    bool public hasBeenUpdated;

    /// @notice Address authorised to call update().
    address public keeper;

    /// @notice Tracked Uniswap V2 pair.
    IUniswapV2Pair public pair;

    /// @notice Decimal precision of `token` (cached from the token contract).
    uint8 public tokenDecimals;

    // ─── TWAP accumulator snapshot ──────────────────────────────────────────────

    uint256 private _price0CumulativeLast;
    uint256 private _price1CumulativeLast;
    uint32 private _blockTimestampLast;

    // true  → pair.token0() == token  → use price0 accumulator (token1/token0 = quote/token)
    // false → pair.token1() == token  → use price1 accumulator (token0/token1 = quote/token)
    bool private _token0IsToken;

    /// @notice Most recently committed TWAP, stored as UQ112x112.
    ///         Multiply by 10^tokenDecimals and shift right by 112 to get quoteToken units.
    uint224 public priceAverageX112;

    // ─── Events ─────────────────────────────────────────────────────────────────

    event TwapActivated(address indexed pair, address indexed keeper);
    event PriceUpdated(uint32 blockTimestamp, uint224 priceAverageX112);

    // ─── Errors ─────────────────────────────────────────────────────────────────

    error ZeroAddress();
    error NotLpActivator();
    error NotKeeper();
    error TwapAlreadyActive();
    error TwapNotActive();
    error InvalidPair();
    error PeriodNotElapsed(uint256 elapsed, uint256 required);
    error PriceOverflow();

    // ─── Constructor ────────────────────────────────────────────────────────────

    /**
     * @param _token        Token to price (e.g. ARC).
     * @param _quoteToken   Quote token (e.g. USDT).
     * @param _lpActivator  Address authorised to call activateTwap exactly once.
     * @param _fixedPrice   Phase-1 price in quoteToken base units (e.g. 300e6 for 300 USDT).
     */
    constructor(address _token, address _quoteToken, address _lpActivator, uint256 _fixedPrice) {
        if (_token == address(0) || _quoteToken == address(0) || _lpActivator == address(0)) {
            revert ZeroAddress();
        }
        token = _token;
        quoteToken = _quoteToken;
        lpActivator = _lpActivator;
        FIXED_PRICE = _fixedPrice;
        tokenDecimals = IERC20Decimals(_token).decimals();
    }

    // ─── Mode switch ────────────────────────────────────────────────────────────

    /**
     * @notice Permanently switches to live TWAP mode.  Callable exactly once.
     * @dev    The supplied pair must contain exactly `token` and `quoteToken`.
     *         Records the current accumulator snapshot so the first update() call
     *         — available PERIOD seconds later — produces a valid TWAP.
     * @param _pair    Uniswap V2 pair address (token/quoteToken in either order).
     * @param _keeper  Address authorised to call update().
     */
    function activateTwap(address _pair, address _keeper) external {
        if (msg.sender != lpActivator) revert NotLpActivator();
        if (twapActive) revert TwapAlreadyActive();
        if (_pair == address(0) || _keeper == address(0)) revert ZeroAddress();

        IUniswapV2Pair _pairContract = IUniswapV2Pair(_pair);
        address t0 = _pairContract.token0();
        address t1 = _pairContract.token1();

        // Pair must contain exactly {token, quoteToken} in either slot order.
        bool tokenIsT0 = (t0 == token && t1 == quoteToken);
        bool tokenIsT1 = (t1 == token && t0 == quoteToken);
        if (!tokenIsT0 && !tokenIsT1) revert InvalidPair();

        (,, uint32 blockTimestampLast) = _pairContract.getReserves();

        pair                  = _pairContract;
        keeper                = _keeper;
        _token0IsToken        = tokenIsT0;
        _price0CumulativeLast = _pairContract.price0CumulativeLast();
        _price1CumulativeLast = _pairContract.price1CumulativeLast();
        _blockTimestampLast   = blockTimestampLast;
        twapActive            = true;

        emit TwapActivated(_pair, _keeper);
    }

    // ─── TWAP update ────────────────────────────────────────────────────────────

    /**
     * @notice Advances the TWAP snapshot.
     * @dev    Only callable by keeper; at least PERIOD must have elapsed since the
     *         previous snapshot (or since activateTwap for the first call).
     */
    function update() external {
        if (!twapActive) revert TwapNotActive();
        if (msg.sender != keeper) revert NotKeeper();

        (uint256 price0Cumulative, uint256 price1Cumulative, uint32 blockTimestamp) =
            _currentCumulativePrices();

        uint32 timeElapsed32;
        unchecked {
            // uint32 subtraction is intentional: handles the ~136-year timestamp wrap.
            timeElapsed32 = blockTimestamp - _blockTimestampLast;
        }
        uint256 timeElapsed = uint256(timeElapsed32);
        if (timeElapsed < PERIOD) revert PeriodNotElapsed(timeElapsed, PERIOD);

        uint256 deltaX112;
        unchecked {
            // Cumulative-price subtractions intentionally wrap (Uniswap V2 accumulator design).
            // _token0IsToken → price0 accumulates quoteToken/token → price of token in quoteToken.
            // otherwise      → price1 accumulates quoteToken/token → same direction.
            deltaX112 = _token0IsToken
                ? (price0Cumulative - _price0CumulativeLast) / timeElapsed
                : (price1Cumulative - _price1CumulativeLast) / timeElapsed;
        }
        if (deltaX112 > type(uint224).max) revert PriceOverflow();

        priceAverageX112      = uint224(deltaX112);
        _price0CumulativeLast = price0Cumulative;
        _price1CumulativeLast = price1Cumulative;
        _blockTimestampLast   = blockTimestamp;
        hasBeenUpdated        = true;

        emit PriceUpdated(blockTimestamp, priceAverageX112);
    }

    // ─── Price query ────────────────────────────────────────────────────────────

    /**
     * @notice Returns the price of one full `token` in `quoteToken` base units.
     * @dev    Returns FIXED_PRICE while TWAP is inactive or not yet updated, so
     *         callers always receive a non-zero price.
     *         Example: 1 ARC = 300 USDT → returns 300_000_000 (6-decimal USDT).
     */
    function getPrice() external view returns (uint256) {
        if (!twapActive || !hasBeenUpdated) return FIXED_PRICE;
        return _decodePriceX112(priceAverageX112, 10 ** uint256(tokenDecimals));
    }

    // ─── View helpers ───────────────────────────────────────────────────────────

    /**
     * @notice Returns true when the keeper may call update() right now.
     */
    function updateReady() external view returns (bool) {
        if (!twapActive) return false;
        (,, uint32 blockTimestamp) = _currentCumulativePrices();
        uint32 elapsed;
        unchecked {
            elapsed = blockTimestamp - _blockTimestampLast;
        }
        return uint256(elapsed) >= PERIOD;
    }

    /**
     * @notice Seconds until the next update() is permitted; 0 if already due;
     *         type(uint256).max if TWAP is not active yet.
     */
    function nextUpdateIn() external view returns (uint256) {
        if (!twapActive) return type(uint256).max;
        (,, uint32 blockTimestamp) = _currentCumulativePrices();
        uint32 elapsed;
        unchecked {
            elapsed = blockTimestamp - _blockTimestampLast;
        }
        uint256 elapsedU = uint256(elapsed);
        return elapsedU >= PERIOD ? 0 : PERIOD - elapsedU;
    }

    // ─── Internal: Uniswap V2 TWAP math ────────────────────────────────────────

    /**
     * @dev Mirrors UniswapV2OracleLibrary.currentCumulativePrices in ^0.8.30.
     *      Interpolates this block's contribution when the pair was last touched
     *      in a previous block.
     */
    function _currentCumulativePrices()
        internal
        view
        returns (uint256 price0Cumulative, uint256 price1Cumulative, uint32 blockTimestamp)
    {
        blockTimestamp   = uint32(block.timestamp % 2 ** 32);
        price0Cumulative = pair.price0CumulativeLast();
        price1Cumulative = pair.price1CumulativeLast();

        (uint112 reserve0, uint112 reserve1, uint32 blockTimestampLast) = pair.getReserves();

        unchecked {
            // Advance cumulative prices by the time elapsed in the current block.
            // Guards: skip if same block (already up-to-date) or zero reserves (no price).
            if (blockTimestampLast != blockTimestamp && reserve0 != 0 && reserve1 != 0) {
                uint32 delta = blockTimestamp - blockTimestampLast;
                // price0 accumulates reserve1/reserve0 in UQ112x112 per second.
                price0Cumulative += _toUQ112x112(reserve1, reserve0) * uint256(delta);
                // price1 accumulates reserve0/reserve1 in UQ112x112 per second.
                price1Cumulative += _toUQ112x112(reserve0, reserve1) * uint256(delta);
            }
        }
    }

    /**
     * @dev Encodes numerator/denominator as UQ112x112 (i.e. numerator * 2^112 / denominator).
     */
    function _toUQ112x112(uint112 numerator, uint112 denominator) internal pure returns (uint256) {
        return (uint256(numerator) << 112) / uint256(denominator);
    }

    /**
     * @dev Computes priceX112 * amountIn >> 112.
     *      Reverts if the multiplication overflows uint256 (only possible for
     *      extreme prices far outside any realistic range).
     */
    function _decodePriceX112(uint224 priceX112, uint256 amountIn) internal pure returns (uint256) {
        uint256 product;
        unchecked {
            product = uint256(priceX112) * amountIn;
        }
        // Overflow detection: if wrapping occurred, reconstructing priceX112 fails.
        if (amountIn != 0 && product / amountIn != uint256(priceX112)) revert PriceOverflow();
        return product >> 112;
    }
}
