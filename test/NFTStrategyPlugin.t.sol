// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import "forge-std/Test.sol";
import "../src/NFTStrategy.sol";
import "../src/NFTStrategyPlugin.sol";
import "../src/NFTStrategyFactory.sol";
import "../src/interfaces/IAlgebraPool.sol";
import "../src/interfaces/IAlgebraFactory.sol";

contract MockERC721 {
    mapping(uint256 => address) public ownerOf;
    mapping(address => uint256) public balanceOf;
    address public owner;
    
    constructor() {
        owner = msg.sender;
    }
    
    function mint(address to, uint256 tokenId) external {
        ownerOf[tokenId] = to;
        balanceOf[to]++;
    }
    
    function transferFrom(address from, address to, uint256 tokenId) external {
        require(ownerOf[tokenId] == from, "Not owner");
        ownerOf[tokenId] = to;
        balanceOf[from]--;
        balanceOf[to]++;
    }
}

contract MockAlgebraPool is IAlgebraPool {
    address public token0;
    address public token1;
    address public plugin;
    uint160 public price = 1 << 96;
    
    constructor(address _token0, address _token1) {
        token0 = _token0;
        token1 = _token1;
    }
    
    function setPlugin(address _plugin) external {
        plugin = _plugin;
    }
    
    function globalState() external view returns (
        uint160 _price,
        int24 tick,
        uint16 lastFee,
        uint8 pluginConfig,
        uint16 communityFee,
        bool unlocked
    ) {
        return (price, 0, 0, 0, 0, true);
    }
    
    function swap(
        address recipient,
        bool zeroToOne,
        int256 amountSpecified,
        uint160 sqrtPriceLimitX96,
        bytes calldata data
    ) external returns (int256 amount0, int256 amount1) {
        // Simplified swap simulation
        if (zeroToOne) {
            amount0 = amountSpecified;
            amount1 = -amountSpecified; // 1:1 for simplicity
        } else {
            amount0 = -amountSpecified;
            amount1 = amountSpecified;
        }
        
        // Call plugin hooks
        if (plugin != address(0)) {
            IAlgebraPlugin(plugin).beforeSwap(msg.sender, recipient, zeroToOne, amountSpecified, sqrtPriceLimitX96, data);
            IAlgebraPlugin(plugin).afterSwap(msg.sender, recipient, zeroToOne, amountSpecified, sqrtPriceLimitX96, amount0, amount1, data);
        }
    }
    
    function mint(
        address sender,
        address recipient,
        int24 bottomTick,
        int24 topTick,
        uint128 liquidityDesired,
        bytes calldata data
    ) external returns (uint256 amount0, uint256 amount1, uint128 liquidityActual) {
        if (plugin != address(0)) {
            IAlgebraPlugin(plugin).beforeModifyPosition(sender, recipient, bottomTick, topTick, int128(liquidityDesired), data);
            IAlgebraPlugin(plugin).afterModifyPosition(sender, recipient, bottomTick, topTick, int128(liquidityDesired), 0, -int256(uint256(liquidityDesired)), data);
        }
        return (0, liquidityDesired, liquidityDesired);
    }
    
    function flash(address recipient, uint256 amount0, uint256 amount1, bytes calldata data) external {
        if (plugin != address(0)) {
            IAlgebraPlugin(plugin).beforeFlash(msg.sender, recipient, amount0, amount1, data);
            IAlgebraPlugin(plugin).afterFlash(msg.sender, recipient, amount0, amount1, amount0, amount1, data);
        }
    }
}

contract MockAlgebraFactory is IAlgebraFactory {
    mapping(address => mapping(address => address)) public pools;
    
    function createPool(address tokenA, address tokenB) external returns (address pool) {
        pool = address(new MockAlgebraPool(tokenA, tokenB));
        pools[tokenA][tokenB] = pool;
        pools[tokenB][tokenA] = pool;
    }
    
    function poolByPair(address tokenA, address tokenB) external view returns (address) {
        return pools[tokenA][tokenB];
    }
    
    function setPluginForPool(address pool, address plugin) external {
        MockAlgebraPool(pool).setPlugin(plugin);
    }
}

contract NFTStrategyPluginTest is Test {
    NFTStrategy public implementation;
    NFTStrategyFactory public factory;
    MockAlgebraFactory public algebraFactory;
    MockERC721 public nftCollection;
    address public punkStrategy;
    address public feeAddress;
    
    NFTStrategy public strategy;
    MockAlgebraPool public pool;
    NFTStrategyPlugin public plugin;
    
    address public user1 = address(0x1);
    address public user2 = address(0x2);
    
    function setUp() public {
        // Deploy mocks
        algebraFactory = new MockAlgebraFactory();
        nftCollection = new MockERC721();
        punkStrategy = address(0x999);
        feeAddress = address(0x888);
        
        // Deploy implementation
        implementation = new NFTStrategy();
        
        // Deploy factory
        factory = new NFTStrategyFactory(
            address(implementation),
            address(algebraFactory),
            punkStrategy,
            feeAddress
        );
        
        // Create NFT strategy
        factory.setLoadingLiquidity(true);
        (address strategyAddr, address poolAddr, address pluginAddr) = factory.createNFTStrategy(
            address(nftCollection),
            "Test NFT Strategy",
            "TNFT",
            0.1 ether
        );
        
        strategy = NFTStrategy(payable(strategyAddr));
        pool = MockAlgebraPool(poolAddr);
        plugin = NFTStrategyPlugin(payable(pluginAddr));
        
        factory.setLoadingLiquidity(false);
        
        // Fund users
        vm.deal(user1, 100 ether);
        vm.deal(user2, 100 ether);
    }
    
    function testPluginDeployment() public view {
        assertEq(address(plugin.pool()), address(pool));
        assertEq(plugin.punkStrategy(), punkStrategy);
        assertEq(plugin.feeAddress(), feeAddress);
    }
    
    function testCalculateFee() public {
        // Initially should be STARTING_BUY_FEE (99%)
        uint128 buyFee = plugin.calculateFee(address(strategy), true);
        assertEq(buyFee, 9900);
        
        // Sell fee should always be DEFAULT_FEE (10%)
        uint128 sellFee = plugin.calculateFee(address(strategy), false);
        assertEq(sellFee, 1000);
        
        // Advance blocks and check fee reduction
        vm.roll(block.number + 50); // 50 blocks = 10 * 5, so 1000 bips reduction
        buyFee = plugin.calculateFee(address(strategy), true);
        assertEq(buyFee, 8900);
        
        // Advance to max reduction
        vm.roll(block.number + 10000);
        buyFee = plugin.calculateFee(address(strategy), true);
        assertEq(buyFee, 1000); // Should cap at DEFAULT_FEE
    }
    
    function testBeforeSwapRejectsExactOutput() public {
        vm.expectRevert(NFTStrategyPlugin.ExactOutputNotAllowed.selector);
        vm.prank(address(pool));
        plugin.beforeSwap(user1, user1, true, 1 ether, 0, "");
    }
    
    function testBeforeSwapOnlyPool() public {
        vm.expectRevert(NFTStrategyPlugin.NotPool.selector);
        vm.prank(user1);
        plugin.beforeSwap(user1, user1, true, -1 ether, 0, "");
    }
    
    function testAfterSwapEmitsEvents() public {
        vm.prank(address(pool));
        
        vm.expectEmit(true, true, false, true);
        emit NFTStrategyPlugin.Trade(address(strategy), 1 << 96, -1 ether, 1 ether);
        
        plugin.afterSwap(user1, user1, true, -1 ether, 0, -1 ether, 1 ether, "");
    }
    
    function testAfterSwapCalculatesFees() public {
        vm.prank(address(pool));
        plugin.afterSwap(user1, user1, true, -1 ether, 0, -1 ether, 1 ether, "");
        
        // Check that fees were accumulated
        uint256 pending = plugin.pendingFees(address(strategy));
        assertGt(pending, 0);
    }
    
    function testProcessFeesDistribution() public {
        // Simulate accumulated fees
        vm.deal(address(plugin), 10 ether);
        
        // Manually set pending fees for testing
        vm.store(
            address(plugin),
            keccak256(abi.encode(address(strategy), uint256(3))), // pendingFees mapping slot
            bytes32(uint256(10 ether))
        );
        
        uint256 strategyBalanceBefore = address(strategy).balance;
        uint256 factoryBalanceBefore = address(factory).balance;
        uint256 feeAddressBalanceBefore = feeAddress.balance;
        
        plugin.processFees(address(strategy));
        
        // Check distribution: 80% to strategy, 10% to factory (punkStrategy), 10% to feeAddress
        assertEq(address(strategy).balance - strategyBalanceBefore, 8 ether);
        assertEq(address(factory).balance - factoryBalanceBefore, 1 ether);
        assertEq(feeAddress.balance - feeAddressBalanceBefore, 1 ether);
    }
    
    function testUpdateFeeAddress() public {
        address newFeeAddress = address(0x777);
        
        vm.prank(factory.owner());
        plugin.updateFeeAddress(newFeeAddress);
        
        assertEq(plugin.feeAddress(), newFeeAddress);
    }
    
    function testUpdateFeeAddressOnlyOwner() public {
        vm.expectRevert(NFTStrategyPlugin.NotNFTStrategyFactoryOwner.selector);
        vm.prank(user1);
        plugin.updateFeeAddress(address(0x777));
    }
    
    function testBeforeModifyPositionOnlyDuringLoading() public {
        vm.expectRevert(NFTStrategyPlugin.NotNFTStrategy.selector);
        vm.prank(address(pool));
        plugin.beforeModifyPosition(user1, user1, 0, 100, 1000, "");
    }
    
    function testBeforeModifyPositionAllowsDuringLoading() public {
        factory.setLoadingLiquidity(true);
        
        vm.prank(address(pool));
        bytes4 selector = plugin.beforeModifyPosition(user1, user1, 0, 100, 1000, "");
        
        assertEq(selector, IAlgebraPlugin.beforeModifyPosition.selector);
        
        factory.setLoadingLiquidity(false);
    }
    
    function testFlashHooks() public {
        vm.prank(address(pool));
        bytes4 beforeSelector = plugin.beforeFlash(user1, user1, 1 ether, 1 ether, "");
        assertEq(beforeSelector, IAlgebraPlugin.beforeFlash.selector);
        
        vm.prank(address(pool));
        bytes4 afterSelector = plugin.afterFlash(user1, user1, 1 ether, 1 ether, 1 ether, 1 ether, "");
        assertEq(afterSelector, IAlgebraPlugin.afterFlash.selector);
    }
}