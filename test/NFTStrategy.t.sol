// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import "forge-std/Test.sol";
import "../src/NFTStrategy.sol";
import "../src/NFTStrategyPlugin.sol";
import "../src/NFTStrategyFactory.sol";
import "./NFTStrategyPlugin.t.sol"; // Reuse mocks

contract NFTStrategyTest is Test {
    NFTStrategy public implementation;
    NFTStrategyFactory public factory;
    MockAlgebraFactory public algebraFactory;
    MockERC721 public nftCollection;
    
    NFTStrategy public strategy;
    MockAlgebraPool public pool;
    NFTStrategyPlugin public plugin;
    
    address public user1 = address(0x1);
    address public marketplace = address(0x3);
    
    function setUp() public {
        algebraFactory = new MockAlgebraFactory();
        nftCollection = new MockERC721();
        
        implementation = new NFTStrategy();
        factory = new NFTStrategyFactory(
            address(implementation),
            address(algebraFactory),
            address(0x999),
            address(0x888)
        );
        
        factory.setLoadingLiquidity(true);
        (address strategyAddr, address poolAddr, address pluginAddr) = factory.createNFTStrategy(
            address(nftCollection),
            "Test NFT",
            "TNFT",
            0.1 ether
        );
        
        strategy = NFTStrategy(payable(strategyAddr));
        pool = MockAlgebraPool(poolAddr);
        plugin = NFTStrategyPlugin(payable(pluginAddr));
        factory.setLoadingLiquidity(false);
        
        vm.deal(user1, 100 ether);
        vm.deal(address(strategy), 10 ether);
    }
    
    function testInitialization() public view {
        assertEq(strategy.name(), "Test NFT");
        assertEq(strategy.symbol(), "TNFT");
        assertEq(address(strategy.collection()), address(nftCollection));
        assertEq(strategy.pluginAddress(), address(plugin));
        assertEq(strategy.totalSupply(), strategy.MAX_SUPPLY());
    }
    
    function testAddFeesOnlyPlugin() public {
        vm.expectRevert(NFTStrategy.OnlyPlugin.selector);
        vm.prank(user1);
        strategy.addFees{value: 1 ether}();
    }
    
    function testAddFees() public {
        uint256 feesBefore = strategy.currentFees();
        
        // Give plugin ETH to send
        vm.deal(address(plugin), 10 ether);
        
        vm.prank(address(plugin));
        strategy.addFees{value: 1 ether}();
        
        assertEq(strategy.currentFees(), feesBefore + 1 ether);
    }
    
    function testIncreaseTransferAllowance() public {
        vm.prank(address(plugin));
        strategy.increaseTransferAllowance(1000);
        
        assertEq(strategy.getTransferAllowance(), 1000);
    }
    
    function testBuyTargetNFT() public {
        // Mint NFT to marketplace
        nftCollection.mint(marketplace, 1);
        
        // Give plugin ETH to send
        vm.deal(address(plugin), 10 ether);
        
        // Add fees to strategy
        vm.prank(address(plugin));
        strategy.addFees{value: 1 ether}();
        
        // Advance blocks to increase max buy price (buyIncrement = 0.1 ether)
        // After 5 blocks: maxPrice = (5 + 1) * 0.1 = 0.6 ether
        vm.roll(block.number + 5);
        
        // Create marketplace contract that will sell the NFT
        MockMarketplace market = new MockMarketplace(address(nftCollection));
        nftCollection.transferFrom(marketplace, address(market), 1);
        
        // Buy NFT
        bytes memory data = abi.encodeWithSelector(MockMarketplace.sellNFT.selector, 1, address(strategy));
        
        vm.prank(user1);
        strategy.buyTargetNFT(0.5 ether, data, 1, address(market));
        
        // Verify NFT was bought
        assertEq(nftCollection.ownerOf(1), address(strategy));
        assertGt(strategy.nftForSale(1), 0);
    }
    
    function testBuyTargetNFTPriceTooHigh() public {
        nftCollection.mint(marketplace, 1);
        
        // Give plugin ETH to send
        vm.deal(address(plugin), 20 ether);
        
        vm.prank(address(plugin));
        strategy.addFees{value: 10 ether}();
        
        // At block 1, maxPrice = (1 + 1) * 0.1 = 0.2 ether
        // Try to buy at 1 ether which is higher than max
        vm.expectRevert(NFTStrategy.PriceTooHigh.selector);
        strategy.buyTargetNFT(1 ether, "", 1, marketplace);
    }
    
    function testSellTargetNFT() public {
        // Setup: Buy NFT first so it's properly listed for sale
        nftCollection.mint(marketplace, 1);
        
        // Give plugin ETH to send
        vm.deal(address(plugin), 10 ether);
        
        // Add fees to strategy
        vm.prank(address(plugin));
        strategy.addFees{value: 2 ether}();
        
        // Advance blocks to increase max buy price
        // After 10 blocks: maxPrice = (10 + 1) * 0.1 = 1.1 ether
        vm.roll(block.number + 10);
        
        // Create marketplace contract that will sell the NFT
        MockMarketplace market = new MockMarketplace(address(nftCollection));
        nftCollection.transferFrom(marketplace, address(market), 1);
        
        // Buy NFT (this will list it for sale)
        bytes memory data = abi.encodeWithSelector(MockMarketplace.sellNFT.selector, 1, address(strategy));
        vm.prank(user1);
        strategy.buyTargetNFT(1 ether, data, 1, address(market));
        
        // Get the sale price
        uint256 salePrice = strategy.nftForSale(1);
        assertGt(salePrice, 0);
        
        // User buys NFT
        vm.prank(user1);
        strategy.sellTargetNFT{value: salePrice}(1);
        
        assertEq(nftCollection.ownerOf(1), user1);
        assertEq(strategy.ethToTwap(), salePrice);
    }
    
    function testSellTargetNFTNotForSale() public {
        vm.expectRevert(NFTStrategy.NFTNotForSale.selector);
        vm.prank(user1);
        strategy.sellTargetNFT{value: 1 ether}(1);
    }
    
    function testProcessTokenTwap() public {
        // Setup: Sell an NFT to generate ethToTwap
        nftCollection.mint(marketplace, 1);
        
        // Give plugin ETH to send
        vm.deal(address(plugin), 10 ether);
        
        // Add fees to strategy
        vm.prank(address(plugin));
        strategy.addFees{value: 2 ether}();
        
        // Advance blocks to increase max buy price
        // After 10 blocks: maxPrice = (10 + 1) * 0.1 = 1.1 ether
        vm.roll(block.number + 10);
        
        // Create marketplace and buy NFT
        MockMarketplace market = new MockMarketplace(address(nftCollection));
        nftCollection.transferFrom(marketplace, address(market), 1);
        
        bytes memory data = abi.encodeWithSelector(MockMarketplace.sellNFT.selector, 1, address(strategy));
        strategy.buyTargetNFT(1 ether, data, 1, address(market));
        
        // Get sale price and sell NFT to generate ethToTwap
        uint256 salePrice = strategy.nftForSale(1);
        vm.prank(user1);
        strategy.sellTargetNFT{value: salePrice}(1);
        
        // Now ethToTwap should have balance
        assertGt(strategy.ethToTwap(), 0);
        
        // Ensure strategy has enough ETH
        vm.deal(address(strategy), 10 ether);
        
        // Advance blocks for TWAP delay
        vm.roll(block.number + 100);
        
        uint256 userBalanceBefore = user1.balance;
        
        vm.prank(user1);
        strategy.processTokenTwap();
        
        // User should receive 0.5% reward
        assertGt(user1.balance, userBalanceBefore);
    }
    
    function testSetPriceMultiplier() public {
        vm.prank(address(factory));
        strategy.setPriceMultiplier(1500);
        
        assertEq(strategy.priceMultiplier(), 1500);
    }
    
    function testSetPriceMultiplierInvalidRange() public {
        vm.expectRevert(NFTStrategy.InvalidMultiplier.selector);
        vm.prank(address(factory));
        strategy.setPriceMultiplier(1000); // Too low
        
        vm.expectRevert(NFTStrategy.InvalidMultiplier.selector);
        vm.prank(address(factory));
        strategy.setPriceMultiplier(11000); // Too high
    }
    
    function testSetDistributor() public {
        vm.prank(strategy.owner());
        strategy.setDistributor(user1, true);
        
        assertTrue(strategy.isDistributor(user1));
    }
    
    function testTransferAllowanceSystem() public {
        // Set allowance
        vm.prank(address(plugin));
        strategy.increaseTransferAllowance(1000 ether);
        
        // Transfer tokens (simulate pool interaction)
        address factoryAddr = strategy.factory();
        vm.prank(factoryAddr);
        strategy.transfer(address(pool), 500 ether);
        
        // Check allowance was reduced
        assertEq(strategy.getTransferAllowance(), 500 ether);
    }
}

contract MockMarketplace {
    IERC721 public nft;
    
    constructor(address _nft) {
        nft = IERC721(_nft);
    }
    
    function sellNFT(uint256 tokenId, address buyer) external payable {
        nft.transferFrom(address(this), buyer, tokenId);
    }
}