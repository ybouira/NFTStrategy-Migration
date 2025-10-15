// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

/// @title NFT Strategy Interface
/// @notice Interface for the NFTStrategy contract adapted for Gliquid
interface INFTStrategy is IERC20 {
    /// @notice Initializes the contract with required addresses and permissions
    /// @param _collection Address of the NFT collection contract
    /// @param _plugin Address of the NFTStrategyPlugin contract
    /// @param _pool Address of the Algebra pool
    /// @param _tokenName Name of the token
    /// @param _tokenSymbol Symbol of the token
    /// @param _buyIncrement Buy increment for the token
    /// @param _owner Owner of the contract
    function initialize(
        address _collection,
        address _plugin,
        address _pool,
        string memory _tokenName,
        string memory _tokenSymbol,
        uint256 _buyIncrement,
        address _owner
    ) external;

    /// @notice Adds trading fees to the contract
    function addFees() external payable;

    /// @notice Increases the transfer allowance for pool operations
    /// @param amountAllowed Amount to add to the current allowance
    function increaseTransferAllowance(uint256 amountAllowed) external;

    /// @notice Gets the current transfer allowance
    function getTransferAllowance() external view returns (uint256);

    /// @notice Returns the NFT collection address
    function collection() external view returns (address);

    /// @notice Returns the plugin address
    function pluginAddress() external view returns (address);

    /// @notice Returns the factory address
    function factory() external view returns (address);

    /// @notice Returns the pool address
    function pool() external view returns (address);
}