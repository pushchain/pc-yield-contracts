# PC Yield Contracts

Smart contracts for yield farming on Push Chain (PC) token ecosystem.

## Architecture

Three staking contracts for different yield farming scenarios:

1. **MigrationYieldFarm** - Epoch-based staking with migration incentives
2. **RewardSeasonsYieldFarm** - Seasonal staking with snapshot-based rewards  
3. **LPYield/UniswapV3Staker** - LP position staking for Uniswap V3

## Prerequisites

```bash
# Install Foundry
curl -L https://foundry.paradigm.xyz | bash
foundryup

# Install Node.js dependencies for Merkle tree generation
npm install
```

## Setup

```bash
# Install Foundry dependencies
forge install

# Build all contracts
forge build

# Run all tests
forge test
```

## Contract Specifications

### MigrationYieldFarm
- Lock period: 90 days (3 months)
- Epoch duration: 21 days
- Cooldown: 1 epoch (21 days)
- Features: Merkle whitelist, epoch-based rewards, migration tracking, upgradeable

### RewardSeasonsYieldFarm
- Season duration: 90 days (3 months)
- Lock period: Full season (no early unstaking)
- Cooldown: 7 days (configurable)
- Features: Merkle whitelist with multipliers, season-end snapshot, combined harvest+unstake

### LPYield/UniswapV3Staker
- Incentive duration: Up to 90 days
- Features: Real-time rewards, time-weighted distribution, multiple incentives, direct LP staking

## Deployment

### MigrationYieldFarm
```bash
# Update script/DeployMigrationYieldFarm.s.sol with:
# - merkleRoot: Whitelist merkle root
# - owner_: Admin address
# - lockDays: Lock period (default: 90)
# - cooldownEpochs: Cooldown in epochs (default: 1)
# - rewardsDays: Epoch duration (default: 21)

forge script script/DeployMigrationYieldFarm.s.sol \
  --rpc-url <your-rpc-url> \
  --private-key <your-private-key> \
  --broadcast
```

### RewardSeasonsYieldFarm
```bash
# Update script/DeployRewardSeasonsYieldFarm.s.sol with:
# - merkleRoot: Whitelist merkle root
# - owner_: Admin address
# - lockPeriod: Season duration (default: 90 days)
# - cooldownPeriod: Cooldown period (default: 7 days)

forge script script/DeployRewardSeasonsYieldFarm.s.sol \
  --rpc-url <your-rpc-url> \
  --private-key <your-private-key> \
  --broadcast
```

### LPYield/UniswapV3Staker
```bash
# Update script/DeployLPYield.s.sol with:
# - factory: Push Chain Uniswap V3 Factory address
# - positionManager: Push Chain Position Manager address
# - maxIncentiveStartLeadTime: Max advance notice (default: 30 days)
# - maxIncentiveDuration: Max incentive duration (default: 90 days)

forge script script/DeployLPYield.s.sol \
  --rpc-url <your-rpc-url> \
  --private-key <your-private-key> \
  --broadcast
```

## Testing

### Run All Tests
```bash
forge test
forge test -v
forge test --gas-report
```

### Contract-Specific Tests
```bash
# MigrationYieldFarm
forge test --match-contract MigrationYieldFarmTest

# RewardSeasonsYieldFarm
forge test --match-contract RewardSeasonsYieldFarmTest

# LPYield/UniswapV3Staker
forge test --match-contract UniswapV3StakerForkTest
```

### Function-Specific Tests
```bash
forge test --match-test test_Stake_NewUser
forge test --match-test test_CompleteRealLifecycleStaking
forge test --match-test test_ReentrancyProtection_Complete

# Pattern matching
forge test --match-test "test_Stake*"
forge test --match-test "*Security*"
```

### Fork Testing
LPYield tests use real Push Chain testnet fork and take longer due to network interaction.

## Merkle Tree Generation

### MigrationYieldFarm Whitelist
```bash
cd scripts
node generate-merkle.js
```

### RewardSeasonsYieldFarm Whitelist
```bash
cd scripts
node generate-reward-merkle.js
```

### Customize Whitelist
Edit the `claims` array in the respective script files:
```javascript
const claims = [
  {
    address: "0x...", // User address
    amount: "1000000000000000000", // Stake amount (wei)
    epoch: 1 // Migration epoch
  }
  // Add more users...
];
```

## Development Commands

### Build
```bash
forge build
forge build --contracts src/MigrationYieldFarm.sol
forge build --use solc:0.8.23
```

### Code Quality
```bash
forge lint
forge fmt
forge inspect --pretty
```

### Gas Analysis
```bash
forge test --match-contract RewardSeasonsYieldFarmTest --gas-report
forge snapshot
```

## Production Deployment

### Pre-Deployment Checklist
- [ ] Update merkle root in deployment scripts
- [ ] Set correct owner address
- [ ] Verify RPC endpoint and network
- [ ] Test deployment on testnet first
- [ ] Verify contract addresses on explorer
- [ ] Test all admin functions
- [ ] Verify merkle proof verification

### Post-Deployment
- [ ] Verify contract initialization
- [ ] Test staking with valid merkle proofs
- [ ] Test reward distribution
- [ ] Test admin functions
- [ ] Monitor for any issues
- [ ] Document deployed addresses

## Repository Structure

```
├── src/
│   ├── MigrationYieldFarm.sol          # Epoch-based staking
│   ├── RewardSeasonsYieldFarm.sol      # Seasonal staking
│   └── LPYield/
│       ├── UniswapV3Staker.sol         # LP position staking
│       ├── interfaces/                  # Contract interfaces
│       └── libraries/                   # Utility libraries
├── script/
│   ├── DeployMigrationYieldFarm.s.sol  # Migration deployment
│   ├── DeployRewardSeasonsYieldFarm.s.sol # Seasonal deployment
│   └── DeployLPYield.s.sol             # LP staking deployment
├── test/
│   ├── MigrationYieldFarm.t.sol        # Migration tests
│   ├── RewardSeasonsYieldFarm.t.sol    # Seasonal tests
│   └── UniswapV3StakerFork.t.sol      # LP staking tests
├── scripts/
│   ├── generate-merkle.js              # Migration whitelist
│   └── generate-reward-merkle.js       # Seasonal whitelist
└── foundry.toml                        # Foundry configuration
```
