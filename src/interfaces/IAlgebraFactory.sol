// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

/// @title Algebra Factory Interface
/// @notice Minimal interface for creating and managing Algebra pools
interface IAlgebraFactory {
    /// @notice Creates a pool for the given two tokens
    /// @param tokenA One of the two tokens in the pool
    /// @param tokenB The other of the two tokens in the pool
    /// @return pool The address of the newly created pool
    function createPool(address tokenA, address tokenB) external returns (address pool);

    /// @notice Returns the pool address for a given pair of tokens
    /// @param tokenA One of the two tokens
    /// @param tokenB The other token
    /// @return pool The pool address
    function poolByPair(address tokenA, address tokenB) external view returns (address pool);

    /// @notice Set the plugin for a pool
    /// @param pool The pool address
    /// @param plugin The plugin address
    function setPluginForPool(address pool, address plugin) external;
}