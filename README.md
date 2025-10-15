# NFTStrategy Migration to Gliquid (Algebra Integral)

This project migrates the NFTStrategy system from Uniswap V4 Hooks to Hyperliquid's Gliquid, which is powered by Algebra Integral.

## Overview

NFTStrategy is an innovative DeFi protocol that combines NFT trading with automated market making. The system:

- Deploys an ERC20 token backed by NFTs from a specific collection
- Uses trading fees from a liquidity pool to automatically purchase NFTs
- Lists purchased NFTs at a markup for resale
- Uses NFT sale proceeds to buy back and burn tokens

## Architecture

### Core Contracts

1. **NFTStrategy.sol** - ERC20 token contract with NFT trading logic (adapted for Gliquid)
2. **NFTStrategyPlugin.sol** - Algebra Integral plugin (replaces Uniswap V4 Hook)
3. **NFTStrategyFactory.sol** - Factory for deploying new NFT strategies

### Key Differences: Uniswap V4 vs Gliquid

| Feature | Uniswap V4 | Gliquid (Algebra Integral) |
|---------|------------|----------------------------|
| **Hook System** | `BaseHook` with permission flags | `IAlgebraPlugin` interface |
| **Pool Manager** | Centralized `PoolManager` | Individual pool contracts |
| **Fee Mechanism** | Hook returns fee delta | Plugin tracks fees separately |
| **Liquidity** | `ModifyLiquidityParams` | Direct `mint`/`burn` calls |
| **Swap Interface** | `SwapParams` struct | Direct parameters |
| **Price Oracle** | `StateLibrary` | `globalState()` on pool |

### Migration Mapping

#### Uniswap V4 Hook → Algebra Plugin

```solidity
// Uniswap V4
function afterSwap(...) returns (bytes4, int128)

// Algebra Integral
function afterSwap(...) returns (bytes4)
```

**Key Changes:**

- Algebra plugins don't return fee deltas directly
- Fee collection handled via separate mechanism
- Plugin must validate `msg.sender == pool`
- No centralized pool manager

#### Pool Interactions

**Uniswap V4:**

```solidity
poolManager.swap(key, params, hookData)
```

**Algebra Integral:**

```solidity
pool.swap(recipient, zeroToOne, amountSpecified, sqrtPriceLimitX96, data)
```

#### Transfer Allowance System

Both systems use transient storage (EIP-1153) for transfer allowances:

- Uniswap V4: Allowance for `PoolManager` transfers
- Gliquid: Allowance for individual `pool` transfers

## Setup

### Prerequisites

- [Foundry](https://book.getfoundry.sh/getting-started/installation)
- Solidity 0.8.26+

### Installation

```bash
# Clone the repository
git clone <repo-url>
cd decentra-solidity

# Install dependencies
forge install OpenZeppelin/openzeppelin-contracts
forge install Vectorized/solady
forge install foundry-rs/forge-std

# Build
forge build
```

### Environment Setup

Copy `.env.example` to `.env` and fill in:

```bash
# RPC URLs
MAINNET_RPC_URL=<your-rpc-url>
HYPERLIQUID_RPC_URL=<hyperliquid-rpc>

# API Keys
ETHERSCAN_API_KEY=your-etherscan-api-key

# Deployment
DEPLOYER_PRIVATE_KEY=your-private-key-here
ALGEBRA_FACTORY=<algebra-factory-address>
PUNK_STRATEGY=<punk-strategy-token>
FEE_ADDRESS=<protocol-fee-recipient>
```

## Testing

```bash
# Run all tests
forge test

# Run with verbosity
forge test -vvv

# Run specific test file
forge test --match-path test/NFTStrategyPlugin.t.sol

# Run with gas reporting
forge test --gas-report
```

### Test Coverage

- **NFTStrategyPlugin.t.sol** - Plugin functionality, fee calculations, hook interactions
- **NFTStrategy.t.sol** - Token mechanics, NFT trading, TWAP buybacks
- **Integration.t.sol** - End-to-end flows

## Deployment

```bash
# Deploy to testnet
forge script script/Deploy.s.sol --rpc-url $HYPERLIQUID_RPC_URL --broadcast

# Deploy to mainnet (use with caution)
forge script script/Deploy.s.sol --rpc-url $MAINNET_RPC_URL --broadcast --verify
```

## Usage

### Creating a New NFT Strategy

```solidity
(address strategy, address pool, address plugin) = factory.createNFTStrategy(
    nftCollectionAddress,
    "My NFT Strategy",
    "MNFT",
    0.1 ether // buyIncrement
);
```

### Trading Flow

1. **User swaps tokens** → Plugin captures fees
2. **Fees accumulate** → Call `plugin.processFees(strategy)`
3. **Strategy buys NFT** → Call `strategy.buyTargetNFT(...)`
4. **NFT listed for sale** → Users can buy via `strategy.sellTargetNFT(...)`
5. **Sale proceeds** → Used for token buyback via `strategy.processTokenTwap()`

## Plugin Hooks

The `NFTStrategyPlugin` implements all Algebra Integral plugin hooks:

- `beforeSwap` - Validates swap parameters (rejects exact output)
- `afterSwap` - Calculates and collects fees, emits trade events
- `beforeModifyPosition` - Restricts liquidity changes to factory
- `afterModifyPosition` - Sets transfer allowances
- `beforeFlash` / `afterFlash` - Flash loan hooks (passthrough)

## Fee Structure

- **Buy Fee**: Starts at 99%, decreases by 1% every 5 blocks to minimum 10%
- **Sell Fee**: Constant 10%

### Fee Distribution

- 80% → NFT Strategy contract (for NFT purchases)
- 10% → PunkStrategy token (buy & burn)
- 10% → Protocol fee address (or collection owner if claimed)

## Security Considerations

1. **Reentrancy Protection** - All external calls protected
2. **Transfer Allowance** - Transient storage prevents unauthorized transfers
3. **Price Limits** - Time-based maximum purchase price
4. **Access Control** - Plugin-only functions, factory-only functions
5. **Upgrade Safety** - UUPS pattern with authorization

## Gas Optimizations

- Solady libraries for gas-efficient ERC20
- Transient storage (EIP-1153) for temporary allowances
- Batch operations in tests

## Known Limitations

1. **Mock Contracts** - Tests use simplified mocks; integration with real Algebra contracts needed
2. **Fee Collection** - Simplified compared to production (needs actual pool fee mechanism)
3. **Price Oracle** - Basic implementation; consider TWAP for production
4. **Flash Loan Hooks** - Passthrough only; could add custom logic
5. **Gas Reporting**: Tests using transient storage (EIP-1153) may fail with `forge test --gas-report` due to Foundry's gas measurement clearing transient state between calls. Run `forge test` without `--gas-report` for accurate test results.

## Future Improvements

- [ ] Integration with real Algebra Integral contracts
- [ ] Advanced fee collection mechanism
- [ ] TWAP price oracle integration
- [ ] Governance system for parameter updates
- [ ] Multi-collection support
- [ ] NFT valuation oracles

## License

MIT

## References

- [Algebra Integral Documentation](https://docs.algebra.finance/)
- [Gliquid Mechanisms](https://gliquids-organization.gitbook.io/jojo-gliquid/)
- [Original NFTStrategy](https://www.nftstrategy.fun/)
- [Uniswap V4 Hooks](https://docs.uniswap.org/contracts/v4/overview)
