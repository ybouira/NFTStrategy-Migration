// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {IAlgebraPlugin} from "./interfaces/IAlgebraPlugin.sol";
import {IAlgebraPool} from "./interfaces/IAlgebraPool.sol";
import {INFTStrategy} from "./interfaces/INFTStrategy.sol";
import {INFTStrategyFactory} from "./interfaces/INFTStrategyFactory.sol";
import {IERC721} from "./interfaces/IERC721.sol";
import {ReentrancyGuard} from "solady/utils/ReentrancyGuard.sol";
import {SafeTransferLib} from "solady/utils/SafeTransferLib.sol";

/// @title NFTStrategyPlugin - Gliquid Plugin for NFTStrategy
/// @author TokenWorks (https://token.works/) - Adapted for Gliquid
/// @notice This plugin manages fee collection and distribution for NFTStrategy pools on Gliquid (Algebra Integral)
/// @dev Implements dynamic fee structure that decreases over time after deployment
contract NFTStrategyPlugin is IAlgebraPlugin, ReentrancyGuard {
    /* ™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™                ™™™™™™™™™™™                ™™™™™™™™™™™ */
    /*                     CONSTANTS                       */
    /* ™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™ */

    /// @notice Total basis points for percentage calculations
    uint128 private constant TOTAL_BIPS = 10000;
    /// @notice Default fee rate (10%)
    uint128 private constant DEFAULT_FEE = 1000;
    /// @notice Starting buy fee rate (99%) - decreases over time
    uint128 private constant STARTING_BUY_FEE = 9900;

    /// @notice The PunkStrategy token contract
    address public immutable punkStrategy;
    /// @notice The NFTStrategyFactory contract
    INFTStrategyFactory public immutable nftStrategyFactory;
    /// @notice The Algebra Pool this plugin is attached to
    IAlgebraPool public immutable pool;
    /// @notice Default address to receive protocol fees
    address public feeAddress;

    /* ™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™ */
    /*                   STATE VARIABLES                   */
    /* ™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™ */

    /// @notice Mapping of collection addresses to their deployment block numbers
    mapping(address => uint256) public deploymentBlock;
    /// @notice Mapping of collection addresses to custom fee recipient addresses
    mapping(address => address) public feeAddressClaimedByOwner;
    /// @notice Accumulated fees waiting to be processed
    mapping(address => uint256) public pendingFees;

    /* ™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™ */
    /*                    CUSTOM ERRORS                    */
    /* ™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™ */

    /// @notice Caller is not an authorized NFTStrategy contract
    error NotNFTStrategy();
    /// @notice Caller is not the NFTStrategyFactory owner
    error NotNFTStrategyFactoryOwner();
    /// @notice Invalid or unrecognized collection address
    error InvalidCollection();
    /// @notice Caller is not the owner of the NFT collection
    error NotCollectionOwner();
    /// @notice Caller is not the pool
    error NotPool();
    /// @notice Exact output swaps are not allowed
    error ExactOutputNotAllowed();

    /* ™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™ */
    /*                    CUSTOM EVENTS                    */
    /* ™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™ */

    /// @notice Emitted when fees are collected from a swap
    event PluginFee(address indexed nftStrategy, address indexed sender, uint256 feeAmount, bool isToken0);
    /// @notice Emitted when a trade occurs in an NFTStrategy pool
    event Trade(address indexed nftStrategy, uint160 sqrtPriceX96, int256 amount0, int256 amount1);
    /// @notice Emitted when fees are distributed
    event FeesDistributed(address indexed nftStrategy, uint256 toStrategy, uint256 toPunkStrategy, uint256 toOwner);

    /* ™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™ */
    /*                     CONSTRUCTOR                     */
    /* ™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™ */

    /// @notice Constructor initializes the plugin with required dependencies
    /// @param _pool The Algebra Pool this plugin is attached to
    /// @param _punkStrategy The PunkStrategy token contract
    /// @param _nftStrategyFactory The NFTStrategyFactory contract
    /// @param _feeAddress Address to send a portion of the fees
    constructor(
        address _pool,
        address _punkStrategy,
        INFTStrategyFactory _nftStrategyFactory,
        address _feeAddress
    ) {
        pool = IAlgebraPool(_pool);
        punkStrategy = _punkStrategy;
        nftStrategyFactory = _nftStrategyFactory;
        feeAddress = _feeAddress;

        // Get the NFT strategy token (token1 in the pool)
        address token1 = pool.token1();
        deploymentBlock[token1] = block.number;
    }

    /* ™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™ */
    /*                  ADMIN FUNCTIONS                    */
    /* ™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™ */

    /// @notice Updates the fee address for receiving protocol fees
    /// @param _feeAddress New address to receive fees
    /// @dev Only callable by the NFTStrategyFactory owner
    function updateFeeAddress(address _feeAddress) external {
        if (msg.sender != nftStrategyFactory.owner()) revert NotNFTStrategyFactoryOwner();
        feeAddress = _feeAddress;
    }

    /// @notice Updates the fee address for a specific NFT strategy collection
    /// @param nftStrategy The NFT strategy contract address
    /// @param destination New address to receive fees for this collection
    /// @dev Only callable by the NFT collection owner
    function updateFeeAddressForCollection(address nftStrategy, address destination) external {
        address collectionAddr = nftStrategyFactory.nftStrategyToCollection(nftStrategy);
        if (collectionAddr == address(0)) revert InvalidCollection();
        if (IERC721(collectionAddr).owner() != msg.sender) revert NotCollectionOwner();
        feeAddressClaimedByOwner[nftStrategy] = destination;
    }

    /// @notice Updates the fee address for a collection by admin or factory
    /// @param nftStrategy The NFT strategy contract address
    /// @param destination New address to receive fees for this collection
    /// @dev Only callable by NFTStrategyFactory owner or the factory contract itself
    function adminUpdateFeeAddress(address nftStrategy, address destination) external {
        if (msg.sender != nftStrategyFactory.owner() && msg.sender != address(nftStrategyFactory)) {
            revert NotNFTStrategyFactoryOwner();
        }
        feeAddressClaimedByOwner[nftStrategy] = destination;
    }

    /* ™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™ */
    /*                  PLUGIN FUNCTIONS                   */
    /* ™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™ */

    /// @notice Called before a swap is executed
    /// @param sender The address initiating the swap
    /// @param zeroToOne The direction of the swap
    /// @param amountSpecified The amount of tokens to swap
    /// @return selector The function selector to confirm execution
    function beforeSwap(
        address sender,
        address, // recipient
        bool zeroToOne,
        int256 amountSpecified,
        uint160, // sqrtPriceLimitX96
        bytes calldata // data
    ) external view override returns (bytes4) {
        if (msg.sender != address(pool)) revert NotPool();
        
        // Restrict exact output swaps
        if (amountSpecified > 0) {
            revert ExactOutputNotAllowed();
        }

        // Silence unused variable warnings
        sender;
        zeroToOne;

        return IAlgebraPlugin.beforeSwap.selector;
    }

    /// @notice Called after a swap is executed
    /// @param sender The address initiating the swap
    /// @param zeroToOne The direction of the swap
    /// @param amountSpecified The amount specified for the swap
    /// @param amount0 The amount of token0 that was swapped
    /// @param amount1 The amount of token1 that was swapped
    /// @return selector The function selector to confirm execution
    function afterSwap(
        address sender,
        address, // recipient
        bool zeroToOne,
        int256 amountSpecified,
        uint160, // sqrtPriceLimitX96
        int256 amount0,
        int256 amount1,
        bytes calldata // data
    ) external override returns (bytes4) {
        if (msg.sender != address(pool)) revert NotPool();

        address token1 = pool.token1();
        address collectionAddr = token1;

        // Silence unused variable warning
        amountSpecified;

        // Determine which amount is the output (positive value)
        bool token0IsOutput = amount0 > 0;
        int256 outputAmount = token0IsOutput ? amount0 : amount1;
        
        if (outputAmount <= 0) {
            return IAlgebraPlugin.afterSwap.selector;
        }

        // Calculate fee based on swap direction
        uint128 currentFee = calculateFee(collectionAddr, zeroToOne);
        uint256 feeAmount = uint256(outputAmount) * currentFee / TOTAL_BIPS;

        if (feeAmount == 0) {
    // Still need to set transfer allowance for the NFT strategy token
    uint256 transferAmount = amount1 < 0 ? uint256(-amount1) : uint256(amount1);
    INFTStrategy(collectionAddr).increaseTransferAllowance(transferAmount);
    return IAlgebraPlugin.afterSwap.selector;
        }

    // Calculate transfer allowance for NFT strategy token
        uint256 collectionAmountToTransfer = amount1 < 0 ? uint256(-amount1) : uint256(amount1);
        
        // If fee is in NFT strategy token, account for it in transfer allowance
        if (!token0IsOutput) {
            collectionAmountToTransfer += feeAmount;
        }

        INFTStrategy(collectionAddr).increaseTransferAllowance(collectionAmountToTransfer);

        // Accumulate fees (in practice, fees are taken by the pool's fee mechanism)
        // For Algebra, we track fees and process them separately
        pendingFees[collectionAddr] += feeAmount;

        emit PluginFee(collectionAddr, sender, feeAmount, token0IsOutput);

        // Get current price and emit trade event
        (uint160 sqrtPriceX96,,,,, ) = pool.globalState();
        emit Trade(collectionAddr, sqrtPriceX96, amount0, amount1);

        return IAlgebraPlugin.afterSwap.selector;
    }

    /// @notice Called before liquidity is modified
    function beforeModifyPosition(
        address, // sender
        address, // recipient
        int24, // bottomTick
        int24, // topTick
        int128, // liquidityDesired
        bytes calldata // data
    ) external view override returns (bytes4) {
        if (msg.sender != address(pool)) revert NotPool();
        
        // Only allow liquidity addition during factory loading
        if (!nftStrategyFactory.loadingLiquidity()) {
            revert NotNFTStrategy();
        }
        
        return IAlgebraPlugin.beforeModifyPosition.selector;
    }

    /// @notice Called after liquidity is modified
    function afterModifyPosition(
        address, // sender
        address, // recipient
        int24, // bottomTick
        int24, // topTick
        int128, // liquidityDesired
        int256, // amount0
        int256 amount1,
        bytes calldata // data
    ) external override returns (bytes4) {
        if (msg.sender != address(pool)) revert NotPool();

        // Set transfer allowance for initial liquidity
        if (nftStrategyFactory.loadingLiquidity() && amount1 < 0) {
            address token1 = pool.token1();
            INFTStrategy(token1).increaseTransferAllowance(uint256(-amount1));
        }

        return IAlgebraPlugin.afterModifyPosition.selector;
    }

    /// @notice Called before a flash loan
    function beforeFlash(
        address, // sender
        address, // recipient
        uint256, // amount0
        uint256, // amount1
        bytes calldata // data
    ) external view override returns (bytes4) {
        if (msg.sender != address(pool)) revert NotPool();
        return IAlgebraPlugin.beforeFlash.selector;
    }

    /// @notice Called after a flash loan
    function afterFlash(
        address, // sender
        address, // recipient
        uint256, // amount0
        uint256, // amount1
        uint256, // paid0
        uint256, // paid1
        bytes calldata // data
    ) external view override returns (bytes4) {
        if (msg.sender != address(pool)) revert NotPool();
        return IAlgebraPlugin.afterFlash.selector;
    }

    /* ™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™ */
    /*                  FEE FUNCTIONS                      */
    /* ™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™ */

    /// @notice Process accumulated fees and distribute them
    /// @param collectionAddr The NFTStrategy collection address
    /// @dev Distributes 80% to collection, 10% to PunkStrategy, 10% to fee address
    function processFees(address collectionAddr) external nonReentrant {
        uint256 feeAmount = pendingFees[collectionAddr];
        if (feeAmount == 0) return;

        pendingFees[collectionAddr] = 0;

        // Calculate 80% for the specific NFTStrategy, 10% for PunkStrategy, and 10% for feeAddress
        uint256 depositAmount = (feeAmount * 80) / 100;
        uint256 pnkstrAmount = (feeAmount * 10) / 100;
        uint256 ownerAmount = feeAmount - depositAmount - pnkstrAmount;

        // Deposit fees into NFTStrategy collection
        INFTStrategy(collectionAddr).addFees{value: depositAmount}();

        // Send fees to nftStrategyFactory to buy and burn PNKSTR
        SafeTransferLib.forceSafeTransferETH(address(nftStrategyFactory), pnkstrAmount);

        // Send remainder to feeAddressClaimedByOwner if claimed, otherwise feeAddress
        address recipient = feeAddressClaimedByOwner[collectionAddr] == address(0) 
            ? feeAddress 
            : feeAddressClaimedByOwner[collectionAddr];
        SafeTransferLib.forceSafeTransferETH(recipient, ownerAmount);

        emit FeesDistributed(collectionAddr, depositAmount, pnkstrAmount, ownerAmount);
    }

    /// @notice Calculates current fee based on deployment block and swap direction
    /// @param collectionAddr The NFTStrategy collection address
    /// @param isBuying True if buying tokens (token0 -> token1), false if selling
    /// @return Current fee in basis points
    /// @dev Buy fees decrease over time from 99% to 10%, sell fees are constant 10%
    function calculateFee(address collectionAddr, bool isBuying) public view returns (uint128) {
        if (!isBuying) return DEFAULT_FEE;

        uint256 deployedAt = deploymentBlock[collectionAddr];
        if (deployedAt == 0) return DEFAULT_FEE;

        uint256 blocksPassed = block.number - deployedAt;
        uint256 feeReductions = (blocksPassed * 100) / 5; // bips to subtract

        uint256 maxReducible = STARTING_BUY_FEE - DEFAULT_FEE;
        if (feeReductions >= maxReducible) return DEFAULT_FEE;

        return uint128(STARTING_BUY_FEE - feeReductions);
    }

    /// @notice Allows the contract to receive ETH
    receive() external payable {}
}