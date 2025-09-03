# PC Yield Contracts

Smart contracts for yield farming on Push Chain (PC) token ecosystem.

## Quick Start

```bash
# Install dependencies
forge install
npm install ethers merkletreejs

# Build and test
forge build
forge test

# Deploy
forge script script/DeployMigrationYieldFarm.s.sol --rpc-url <rpc> --private-key <key> --broadcast
```

## Contracts

- **MigrationYieldFarm**: Main staking contract with epoch-based rewards
- **UniswapV3Staker**: LP position staking for Uniswap V3

## Architecture

- **Epoch-based Staking**: Configurable epochs with cumulative stake tracking
- **Merkle Whitelist**: Address validation using Merkle proofs
- **Lock Periods**: Configurable lock and cooldown periods
- **Proxy Pattern**: TransparentUpgradeableProxy for upgradeable contracts

## Key Functions

```solidity
// User functions
function stake(bytes32[] calldata proof, uint256 amount, uint256 epoch) external payable
function requestUnstake(uint256 amount) external
function withdraw() external
function harvestRewards() external

// Admin functions
function addCurrentEpochReward() external payable
function setMerkleRoot(bytes32 _merkleRoot) external onlyOwner
```

## Testing

```bash
# Run all tests
forge test

# Run specific test
forge test --match-test test_7_HighTrafficStressTest

# Gas report
forge test --gas-report
```

## Merkle Tree

Generate whitelist using the provided script:
```bash
cd scripts && node generate-merkle.js
```

## License

MIT
