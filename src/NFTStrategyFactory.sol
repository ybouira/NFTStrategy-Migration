// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Ownable} from "solady/auth/Ownable.sol";
import {LibClone} from "solady/utils/LibClone.sol";
import {IAlgebraFactory} from "./interfaces/IAlgebraFactory.sol";
import {INFTStrategy} from "./interfaces/INFTStrategy.sol";
import {INFTStrategyFactory} from "./interfaces/INFTStrategyFactory.sol";
import {NFTStrategyPlugin} from "./NFTStrategyPlugin.sol";

contract NFTStrategyFactory is Ownable {
    address public immutable nftStrategyImplementation;
    address public immutable algebraFactory;
    address public punkStrategy;
    address public feeAddress;
    
    bool public loadingLiquidity;
    mapping(address => address) public nftStrategyToCollection;
    
    event NFTStrategyCreated(address indexed strategy, address indexed collection, address indexed pool);
    
    constructor(address _implementation, address _algebraFactory, address _punkStrategy, address _feeAddress) {
        _initializeOwner(msg.sender);
        nftStrategyImplementation = _implementation;
        algebraFactory = _algebraFactory;
        punkStrategy = _punkStrategy;
        feeAddress = _feeAddress;
    }
    
    function createNFTStrategy(
        address collection,
        string memory name,
        string memory symbol,
        uint256 buyIncrement
    ) external returns (address strategy, address pool, address plugin) {
        // Deploy strategy via proxy
        bytes memory immutableArgs = abi.encodePacked(address(this));
        strategy = LibClone.deployERC1967(nftStrategyImplementation, immutableArgs);
        
        // Create pool
        pool = IAlgebraFactory(algebraFactory).createPool(address(0), strategy);
        
        // Deploy plugin - cast this to INFTStrategyFactory
        plugin = address(new NFTStrategyPlugin(pool, punkStrategy, INFTStrategyFactory(address(this)), feeAddress));
        
        // Set plugin for pool
        IAlgebraFactory(algebraFactory).setPluginForPool(pool, plugin);
        
        // Initialize strategy
        INFTStrategy(strategy).initialize(collection, plugin, pool, name, symbol, buyIncrement, msg.sender);
        
        nftStrategyToCollection[strategy] = collection;
        
        emit NFTStrategyCreated(strategy, collection, pool);
    }
    
    function setLoadingLiquidity(bool _loading) external onlyOwner {
        loadingLiquidity = _loading;
    }
}