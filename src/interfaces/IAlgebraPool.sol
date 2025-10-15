// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

/// @title Algebra Pool Interface
/// @notice Minimal interface for Algebra Integral pools
interface IAlgebraPool {
    /// @notice The first of the two tokens of the pool, sorted by address
    function token0() external view returns (address);

    /// @notice The second of the two tokens of the pool, sorted by address
    function token1() external view returns (address);

    /// @notice The plugin attached to this pool
    function plugin() external view returns (address);

    /// @notice The current price of the pool
    function globalState()
        external
        view
        returns (
            uint160 price,
            int24 tick,
            uint16 lastFee,
            uint8 pluginConfig,
            uint16 communityFee,
            bool unlocked
        );

    /// @notice Swap tokens in the pool
    function swap(
        address recipient,
        bool zeroToOne,
        int256 amountSpecified,
        uint160 sqrtPriceLimitX96,
        bytes calldata data
    ) external returns (int256 amount0, int256 amount1);

    /// @notice Add liquidity to the pool
    function mint(
        address sender,
        address recipient,
        int24 bottomTick,
        int24 topTick,
        uint128 liquidityDesired,
        bytes calldata data
    ) external returns (uint256 amount0, uint256 amount1, uint128 liquidityActual);

    /// @notice Receive token0 and/or token1 and pay it back, plus a fee, in the callback
    function flash(
        address recipient,
        uint256 amount0,
        uint256 amount1,
        bytes calldata data
    ) external;
}