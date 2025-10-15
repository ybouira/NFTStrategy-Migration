// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

/// @title NFT Strategy Factory Interface
/// @notice Interface for the NFTStrategyFactory contract
interface INFTStrategyFactory {
    /// @notice Returns the owner of the factory
    function owner() external view returns (address);

    /// @notice Indicates if liquidity is currently being loaded
    function loadingLiquidity() external view returns (bool);

    /// @notice Maps NFT strategy addresses to their collection addresses
    function nftStrategyToCollection(address nftStrategy) external view returns (address);

    /// @notice Returns the PunkStrategy token address
    function punkStrategy() external view returns (address);
}