// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {ERC20} from "solady/tokens/ERC20.sol";
import {ReentrancyGuard} from "solady/utils/ReentrancyGuard.sol";
import {SafeTransferLib} from "solady/utils/SafeTransferLib.sol";
import {Initializable} from "solady/utils/Initializable.sol";
import {UUPSUpgradeable} from "solady/utils/UUPSUpgradeable.sol";
import {Ownable} from "solady/auth/Ownable.sol";
import {LibClone} from "solady/utils/LibClone.sol";
import {IAlgebraPool} from "./interfaces/IAlgebraPool.sol";
import {IERC721} from "./interfaces/IERC721.sol";

/// @title NFTStrategy - An ERC20 token that constantly churns NFTs from a collection
/// @author TokenWorks ([https://token.works/](https://token.works/)) - Adapted for Gliquid
/// @notice This contract implements an ERC20 token backed by NFTs from a specific collection.
///         Users can trade the token on Gliquid (Algebra Integral), and the contract uses trading fees to buy and sell NFTs.
/// @dev Uses ERC1967 proxy pattern with immutable args for gas-efficient upgrades
contract NFTStrategy is Initializable, UUPSUpgradeable, Ownable, ReentrancyGuard, ERC20 {
    /* ™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™ */
    /*                     CONSTANTS                       */
    /* ™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™ */

    /// @notice The name of the ERC20 token
    string tokenName;
    /// @notice The symbol of the ERC20 token
    string tokenSymbol;
    /// @notice Address of the Gliquid plugin contract
    address public pluginAddress;
    /// @notice The NFT collection this strategy is tied to
    IERC721 public collection;
    /// @notice Maximum token supply (1 billion tokens)
    uint256 public constant MAX_SUPPLY = 1_000_000_000 * 1e18;
    /// @notice Dead address for burning tokens
    address public constant DEAD_ADDRESS = 0x000000000000000000000000000000000000dEaD;
    /// @notice Contract version for upgrade tracking
    uint256 public constant VERSION = 2;

    /* ™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™ */
    /*                   STATE VARIABLES                   */
    /* ™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™ */

    /// @notice Multiplier for NFT resale price (in basis points, e.g., 1200 = 1.2x)
    uint256 public priceMultiplier;
    /// @notice Mapping of NFT token IDs to their sale prices
    mapping(uint256 => uint256) public nftForSale;
    /// @notice Current accumulated fees available for NFT purchases
    uint256 public currentFees;
    /// @notice ETH accumulated from NFT sales, waiting to be used for token buyback
    uint256 public ethToTwap;
    /// @notice Amount of ETH to use per TWAP buyback operation
    uint256 public twapIncrement;
    /// @notice Number of blocks to wait between TWAP operations
    uint256 public twapDelayInBlocks;
    /// @notice Block number of the last TWAP operation
    uint256 public lastTwapBlock;
    /// @notice Block number when the last NFT was bought
    uint256 public lastBuyBlock;
    /// @notice ETH amount increment for maximum buy price calculation
    uint256 public buyIncrement;
    /// @notice Mapping of addresses that can distribute tokens freely (team wallets, airdrop contracts)
    mapping(address => bool) public isDistributor;
    /// @notice The Algebra pool address for this strategy
    address public pool;

    /// @notice Storage gap for future upgrades (prevents storage collisions)
    uint256[48] private __gap;

    /* ™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™ */
    /*                   CUSTOM EVENTS                     */
    /* ™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™ */

    /// @notice Emitted when the protocol buys an NFT
    event NFTBoughtByProtocol(uint256 indexed tokenId, uint256 purchasePrice, uint256 listPrice);
    /// @notice Emitted when the protocol sells an NFT
    event NFTSoldByProtocol(uint256 indexed tokenId, uint256 price, address buyer);
    /// @notice Emitted when transfer allowance is increased by the plugin
    event AllowanceIncreased(uint256 amount);
    /// @notice Emitted when transfer allowance is spent
    event AllowanceSpent(address indexed from, address indexed to, uint256 amount);
    /// @notice Emitted when the contract implementation is upgraded
    event ContractUpgraded(address indexed oldImplementation, address indexed newImplementation, uint256 version);
    /// @notice Emitted when a distributor's whitelist status is updated
    event DistributorUpdated(address indexed distributor, bool status);

    /* ™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™ */
    /*                    CUSTOM ERRORS                    */
    /* ™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™ */

    /// @notice NFT is not currently for sale
    error NFTNotForSale();
    /// @notice Sent ETH amount is less than the NFT sale price
    error NFTPriceTooLow();
    /// @notice Contract doesn't have enough ETH balance
    error InsufficientContractBalance();
    /// @notice Price multiplier is outside valid range
    error InvalidMultiplier();
    /// @notice No ETH available for TWAP operations
    error NoETHToTwap();
    /// @notice Not enough blocks have passed since last TWAP
    error TwapDelayNotMet();
    /// @notice Not enough ETH in fees to make purchase
    error NotEnoughEth();
    /// @notice Purchase price exceeds time-based maximum
    error PriceTooHigh();
    /// @notice Caller is not the factory contract
    error NotFactory();
    /// @notice Contract already owns this NFT
    error AlreadyNFTOwner();
    /// @notice External call didn't result in NFT acquisition
    error NeedToBuyNFT();
    /// @notice Contract doesn't own the specified NFT
    error NotNFTOwner();
    /// @notice Caller is not the authorized plugin contract
    error OnlyPlugin();
    /// @notice Invalid NFT collection address
    error InvalidCollection();
    /// @notice External call to marketplace failed
    error ExternalCallFailed(bytes reason);
    /// @notice Invalid target address for external call
    error InvalidTarget();
    /// @notice Token transfer not authorized
    error InvalidTransfer();

    /* ™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™ */
    /*                    CONSTRUCTOR                      */
    /* ™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™ */

    /// @notice Constructor disables initializers to prevent implementation contract initialization
    constructor() {
        _disableInitializers();
    }

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
    ) external initializer {
        require(_collection != address(0), "Invalid collection");
        require(bytes(_tokenName).length > 0, "Empty name");
        require(bytes(_tokenSymbol).length > 0, "Empty symbol");

        collection = IERC721(_collection);
        pluginAddress = _plugin;
        pool = _pool;
        tokenName = _tokenName;
        tokenSymbol = _tokenSymbol;
        lastBuyBlock = block.number;
        buyIncrement = _buyIncrement;

        _initializeOwner(_owner);

        // Initialize state variables with default values
        priceMultiplier = 1200; // 1.2x
        twapIncrement = 1 ether;
        twapDelayInBlocks = 1;

        _mint(factory(), MAX_SUPPLY);
    }

    /* ™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™ */
    /*                     MODIFIERS                       */
    /* ™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™ */

    /// @notice Restricts function access to the factory contract only
    modifier onlyFactory() {
        if (msg.sender != factory()) revert NotFactory();
        _;
    }

    /* ™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™ */
    /*                   ADMIN FUNCTIONS                   */
    /* ™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™ */

    /// @notice Authorizes contract upgrades (UUPS pattern)
    function _authorizeUpgrade(address newImplementation) internal override onlyOwner {
        require(newImplementation != address(0), "Invalid implementation");
        require(newImplementation.code.length > 0, "Implementation must be contract");
        emit ContractUpgraded(address(this), newImplementation, VERSION);
    }

    /// @notice Updates the plugin address
    function updatePluginAddress(address _pluginAddress) external onlyOwner {
        pluginAddress = _pluginAddress;
    }

    /// @notice Returns the name of the token
    function name() public view override returns (string memory) {
        return tokenName;
    }

    /// @notice Returns the symbol of the token
    function symbol() public view override returns (string memory) {
        return tokenSymbol;
    }

    /* ™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™ */
    /*                   FACTORY FUNCTIONS                 */
    /* ™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™ */

    /// @notice Updates the name of the token
    function updateName(string memory _tokenName) external onlyFactory {
        tokenName = _tokenName;
    }

    /// @notice Updates the symbol of the token
    function updateSymbol(string memory _tokenSymbol) external onlyFactory {
        tokenSymbol = _tokenSymbol;
    }

        /// @notice Updates the price multiplier for relisting NFTs
    function setPriceMultiplier(uint256 _newMultiplier) external onlyFactory {
        if (_newMultiplier < 1100 || _newMultiplier > 10000) revert InvalidMultiplier();
        priceMultiplier = _newMultiplier;
    }

    /// @notice Allows owner to whitelist addresses that can distribute tokens freely
    function setDistributor(address distributor, bool status) external onlyOwner {
        isDistributor[distributor] = status;
        emit DistributorUpdated(distributor, status);
    }

    /* ™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™ */
    /*                 MECHANISM FUNCTIONS                 */
    /* ™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™ */

    function getMaxPriceForBuy() public view returns (uint256) {
        uint256 blocksSinceLastBuy = block.number - lastBuyBlock;
        return (blocksSinceLastBuy + 1) * buyIncrement;
    }

    function addFees() external payable {
        if (msg.sender != pluginAddress) revert OnlyPlugin();
        currentFees += msg.value;
    }

    /// @notice Increases the transient transfer allowance for pool operations
    /// @param amountAllowed Amount to add to the current allowance
    /// @dev Uses EIP-1153 transient storage for gas-efficient temporary allowances.
    ///      The allowance is consumed by _afterTokenTransfer during token transfers
    ///      and automatically cleared at the end of the transaction. This design is
    ///      safe because: (1) only the plugin can set allowances, (2) transfers
    ///      validate and decrement the allowance, (3) unauthorized transfers revert.
    function increaseTransferAllowance(uint256 amountAllowed) external {
        if (msg.sender != pluginAddress) revert OnlyPlugin();
        uint256 currentAllowance = getTransferAllowance();
        assembly {
            tstore(0, add(currentAllowance, amountAllowed))
        }
        emit AllowanceIncreased(amountAllowed);
    }

    function buyTargetNFT(uint256 value, bytes calldata data, uint256 expectedId, address target)
        external
        nonReentrant
    {
        uint256 ethBalanceBefore = address(this).balance;
        uint256 nftBalanceBefore = collection.balanceOf(address(this));

        if (collection.ownerOf(expectedId) == address(this)) revert AlreadyNFTOwner();
        if (value > currentFees) revert NotEnoughEth();
        if (value > getMaxPriceForBuy()) revert PriceTooHigh();
        if (target == address(collection)) revert InvalidTarget();

        (bool success, bytes memory reason) = target.call{value: value}(data);
        if (!success) revert ExternalCallFailed(reason);

        uint256 nftBalanceAfter = collection.balanceOf(address(this));
        if (nftBalanceAfter != nftBalanceBefore + 1) revert NeedToBuyNFT();
        if (collection.ownerOf(expectedId) != address(this)) revert NotNFTOwner();

        uint256 cost = ethBalanceBefore - address(this).balance;
        currentFees -= cost;

        uint256 salePrice = cost * priceMultiplier / 1000;
        nftForSale[expectedId] = salePrice;
        lastBuyBlock = block.number;

        emit NFTBoughtByProtocol(expectedId, cost, salePrice);
    }

    function sellTargetNFT(uint256 tokenId) external payable nonReentrant {
        uint256 salePrice = nftForSale[tokenId];
        if (salePrice == 0) revert NFTNotForSale();
        if (msg.value != salePrice) revert NFTPriceTooLow();
        if (collection.ownerOf(tokenId) != address(this)) revert NotNFTOwner();

        collection.transferFrom(address(this), msg.sender, tokenId);
        delete nftForSale[tokenId];
        ethToTwap += salePrice;

        emit NFTSoldByProtocol(tokenId, salePrice, msg.sender);
    }

    function processTokenTwap() external nonReentrant {
        if (ethToTwap == 0) revert NoETHToTwap();
        if (block.number < lastTwapBlock + twapDelayInBlocks) revert TwapDelayNotMet();

        uint256 burnAmount = twapIncrement;
        if (ethToTwap < twapIncrement) burnAmount = ethToTwap;

        uint256 reward = (burnAmount * 5) / 1000;
        burnAmount -= reward;

        ethToTwap -= burnAmount + reward;
        lastTwapBlock = block.number;

        _buyAndBurnTokens(burnAmount);
        SafeTransferLib.forceSafeTransferETH(msg.sender, reward);
    }

    /* ™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™ */
    /*                  INTERNAL FUNCTIONS                 */
    /* ™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™ */

    function _buyAndBurnTokens(uint256 amountIn) internal {
        // Swap ETH for tokens via Algebra pool and send to dead address
        IAlgebraPool(pool).swap(
            DEAD_ADDRESS,
            true, // zeroForOne (ETH -> token)
            -int256(amountIn),
            type(uint160).max - 1,
            ""
        );
    }

    function _afterTokenTransfer(address from, address to, uint256 amount) internal override {
        if (from == address(0)) return;
        if (isDistributor[from]) return;

        if ((from == pool || to == pool)) {
            uint256 transferAllowance = getTransferAllowance();
            require(transferAllowance >= amount, InvalidTransfer());
            assembly {
                let newAllowance := sub(transferAllowance, amount)
                tstore(0, newAllowance)
            }
            emit AllowanceSpent(from, to, amount);
            return;
        }
        revert InvalidTransfer();
    }

    function getTransferAllowance() public view returns (uint256 transferAllowance) {
        assembly {
            transferAllowance := tload(0)
        }
    }

    function onERC721Received(address, address, uint256, bytes calldata) external view returns (bytes4) {
        if (msg.sender != address(collection)) revert InvalidCollection();
        return this.onERC721Received.selector;
    }

    /* ™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™ */
    /*                  GETTER FUNCTIONS                   */
    /* ™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™ */

    function factory() public view returns (address) {
        bytes memory args = LibClone.argsOnERC1967(address(this), 0, 20);
        return address(bytes20(args));
    }

    function getImplementation() external view returns (address result) {
        assembly {
            result := sload(_ERC1967_IMPLEMENTATION_SLOT)
        }
    }

    receive() external payable {}
}