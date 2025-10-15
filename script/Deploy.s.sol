// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import "forge-std/Script.sol";
import "../src/NFTStrategy.sol";
import "../src/NFTStrategyFactory.sol";

contract DeployScript is Script {
    function run() external {
        uint256 deployerPrivateKey = vm.envUint("DEPLOYER_PRIVATE_KEY");
        address algebraFactory = vm.envAddress("ALGEBRA_FACTORY");
        address punkStrategy = vm.envAddress("PUNK_STRATEGY");
        address feeAddress = vm.envAddress("FEE_ADDRESS");
        
        vm.startBroadcast(deployerPrivateKey);
        
        // Deploy implementation
        NFTStrategy implementation = new NFTStrategy();
        
        // Deploy factory
        NFTStrategyFactory factory = new NFTStrategyFactory(
            address(implementation),
            algebraFactory,
            punkStrategy,
            feeAddress
        );
        
        vm.stopBroadcast();
        
        console.log("Implementation:", address(implementation));
        console.log("Factory:", address(factory));
    }
}