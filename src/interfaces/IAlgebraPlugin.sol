// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

/// @title Algebra Integral Plugin Interface
/// @notice Interface for plugins in Algebra Integral (Gliquid)
/// @dev Plugins can hook into swap, mint, burn, and flash operations
interface IAlgebraPlugin {
    /// @notice Called before a swap is executed
    /// @param sender The address initiating the swap
    /// @param recipient The address receiving the output tokens
    /// @param zeroToOne The direction of the swap (token0 -> token1 or vice versa)
    /// @param amountSpecified The amount of tokens to swap
    /// @param sqrtPriceLimitX96 The price limit for the swap
    /// @param data Additional data passed to the plugin
    /// @return selector The function selector to confirm execution
    function beforeSwap(
        address sender,
        address recipient,
        bool zeroToOne,
        int256 amountSpecified,
        uint160 sqrtPriceLimitX96,
        bytes calldata data
    ) external returns (bytes4 selector);

    /// @notice Called after a swap is executed
    /// @param sender The address initiating the swap
    /// @param recipient The address receiving the output tokens
    /// @param zeroToOne The direction of the swap
    /// @param amountSpecified The amount of tokens to swap
    /// @param sqrtPriceLimitX96 The price limit for the swap
    /// @param amount0 The amount of token0 that was swapped
    /// @param amount1 The amount of token1 that was swapped
    /// @param data Additional data passed to the plugin
    /// @return selector The function selector to confirm execution
    function afterSwap(
        address sender,
        address recipient,
        bool zeroToOne,
        int256 amountSpecified,
        uint160 sqrtPriceLimitX96,
        int256 amount0,
        int256 amount1,
        bytes calldata data
    ) external returns (bytes4 selector);

    /// @notice Called before liquidity is added
    /// @param sender The address adding liquidity
    /// @param recipient The address receiving the liquidity position
    /// @param bottomTick The lower tick of the position
    /// @param topTick The upper tick of the position
    /// @param liquidityDesired The amount of liquidity to add
    /// @param data Additional data passed to the plugin
    /// @return selector The function selector to confirm execution
    function beforeModifyPosition(
        address sender,
        address recipient,
        int24 bottomTick,
        int24 topTick,
        int128 liquidityDesired,
        bytes calldata data
    ) external returns (bytes4 selector);

    /// @notice Called after liquidity is added
    /// @param sender The address adding liquidity
    /// @param recipient The address receiving the liquidity position
    /// @param bottomTick The lower tick of the position
    /// @param topTick The upper tick of the position
    /// @param liquidityDesired The amount of liquidity to add
    /// @param amount0 The amount of token0 added
    /// @param amount1 The amount of token1 added
    /// @param data Additional data passed to the plugin
    /// @return selector The function selector to confirm execution
    function afterModifyPosition(
        address sender,
        address recipient,
        int24 bottomTick,
        int24 topTick,
        int128 liquidityDesired,
        int256 amount0,
        int256 amount1,
        bytes calldata data
    ) external returns (bytes4 selector);

    /// @notice Called before a flash loan is executed
    /// @param sender The address initiating the flash
    /// @param recipient The address receiving the flash loan
    /// @param amount0 The amount of token0 to flash
    /// @param amount1 The amount of token1 to flash
    /// @param data Additional data passed to the plugin
    /// @return selector The function selector to confirm execution
    function beforeFlash(
        address sender,
        address recipient,
        uint256 amount0,
        uint256 amount1,
        bytes calldata data
    ) external returns (bytes4 selector);

    /// @notice Called after a flash loan is executed
    /// @param sender The address initiating the flash
    /// @param recipient The address receiving the flash loan
    /// @param amount0 The amount of token0 flashed
    /// @param amount1 The amount of token1 flashed
    /// @param paid0 The amount of token0 paid back
    /// @param paid1 The amount of token1 paid back
    /// @param data Additional data passed to the plugin
    /// @return selector The function selector to confirm execution
    function afterFlash(
        address sender,
        address recipient,
        uint256 amount0,
        uint256 amount1,
        uint256 paid0,
        uint256 paid1,
        bytes calldata data
    ) external returns (bytes4 selector);
}