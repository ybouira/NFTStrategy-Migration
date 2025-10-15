// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import "forge-std/Test.sol";
import "./NFTStrategyPlugin.t.sol";

contract MockMarketplace {
    IERC721 public nft;
    
    constructor(address _nft) {
        nft = IERC721(_nft);
    }
    
    function sellNFT(uint256 tokenId, address buyer) external payable {
        nft.transferFrom(address(this), buyer, tokenId);
    }
}

contract IntegrationTest is Test {
    NFTStrategy public implementation;
    NFTStrategyFactory public factory;
    MockAlgebraFactory public algebraFactory;
    MockERC721 public nftCollection;
    
    NFTStrategy public strategy;
    MockAlgebraPool public pool;
    NFTStrategyPlugin public plugin;
    
    address public user1 = address(0x1);
    address public user2 = address(0x2);
    
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
            "Integrated NFT",
            "INFT",
            0.1 ether
        );
        
        strategy = NFTStrategy(payable(strategyAddr));
        pool = MockAlgebraPool(poolAddr);
        plugin = NFTStrategyPlugin(payable(pluginAddr));
        factory.setLoadingLiquidity(false);
        
        vm.deal(user1, 100 ether);
        vm.deal(user2, 100 ether);
    }
    
    function testFullSwapFlow() public {
        // Simulate a swap through the pool
        vm.prank(user1);
        pool.swap(user1, true, -1 ether, type(uint160).max - 1, "");
        
        // Verify fees were accumulated
        assertGt(plugin.pendingFees(address(strategy)), 0);
    }
    
    function testFullNFTPurchaseAndSaleFlow() public {
        // Give plugin ETH to send
        vm.deal(address(plugin), 10 ether);
        
        // Add fees
        vm.prank(address(plugin));
        strategy.addFees{value: 5 ether}();
        
        // Advance blocks to increase max buy price (buyIncrement = 0.1 ether)
        // After 10 blocks: maxPrice = (10 + 1) * 0.1 = 1.1 ether
        vm.roll(block.number + 10);
        
        // Mint NFT and setup marketplace
        nftCollection.mint(address(this), 1);
        MockMarketplace market = new MockMarketplace(address(nftCollection));
        nftCollection.transferFrom(address(this), address(market), 1);
        
        // Buy NFT
        bytes memory data = abi.encodeWithSelector(MockMarketplace.sellNFT.selector, 1, address(strategy));
        strategy.buyTargetNFT(1 ether, data, 1, address(market));
        
        // Verify NFT is for sale
        uint256 salePrice = strategy.nftForSale(1);
        assertGt(salePrice, 1 ether); // Should be marked up
        
        // User buys NFT
        vm.prank(user2);
        strategy.sellTargetNFT{value: salePrice}(1);
        
        // Verify transfer
        assertEq(nftCollection.ownerOf(1), user2);
        assertEq(strategy.ethToTwap(), salePrice);
    }
}