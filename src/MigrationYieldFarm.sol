// SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

import {IERC20} from "@openzeppelin-v5/contracts/token/ERC20/IERC20.sol";
import {Ownable} from "@openzeppelin-v5/contracts/access/Ownable.sol";
import {ReentrancyGuard} from "@openzeppelin-v5/contracts/utils/ReentrancyGuard.sol";
import {MerkleProof} from "@openzeppelin-v5/contracts/utils/cryptography/MerkleProof.sol";
import {Initializable} from "@openzeppelin-v5/contracts/proxy/utils/Initializable.sol";

/// @title MigrationYieldFarm
/// @notice Migration-based staking program for users who migrated from ERC20 PUSH to native PC tokens.
/// @dev Features: 3-month lock, epoch-based cooldown, 21-day reward epochs, 20% APR target.
/// @dev Transparent upgradeable contract using TransparentUpgradeableProxy pattern.
/// @dev Migration proof validation using (recipient, amount, migrationEpoch) Merkle tree.
/// @dev Note: migrationEpoch is for proof uniqueness only, staking epochs are for reward distribution.
contract MigrationYieldFarm is Ownable, ReentrancyGuard, Initializable {
    // --------------------------------------------------
    // Program configuration
    // --------------------------------------------------
    // Staking and rewards are in native PC (payable)
    bytes32 public merkleRoot; // migration proof: keccak256(abi.encodePacked(recipient, amount, migrationEpoch))
    uint256 public lockPeriod; // 3 months (in blocks)
    uint256 public cooldownPeriod; // 14 days (in blocks)

    // Epoch configuration (21 days)
    uint256 public epochDuration; // epoch duration in blocks (1,814,400 blocks for 1-second blocks)
    uint256 public genesisEpoch; // block number when staking started

    // Epoch-based rewards - like PushCoreV2 but simplified
    mapping(uint256 => uint256) public epochRewards; // rewards per epoch
    mapping(uint256 => uint256) public epochToTotalStaked; // total staked per epoch

    address public rewardsDistributor; // optional role allowed to fund epochs

    // --------------------------------------------------
    // Staking state
    // --------------------------------------------------
    uint256 public totalStaked; // total staked by all users

    // User staking info
    struct UserStakeInfo {
        uint256 stakedAmount;
        uint256 lastClaimedBlock;
        uint256 lastStakedBlock;
        bool isRegistered; // Track if user has been validated with Merkle proof
        mapping(uint256 => uint256) epochToUserStakedAmount;
    }

    mapping(address => UserStakeInfo) public userStakeInfo;
    mapping(address => uint256) public usersRewardsClaimed;

    // Lock end per user (no unstake allowed before this block)
    mapping(address => uint256) public lockEndBlock;

    // Cooldown withdrawal state (single pending request model)
    mapping(address => uint256) public pendingWithdrawalAmount;
    mapping(address => uint256) public withdrawalReadyAtBlock;

    // --------------------------------------------------
    // Events
    // --------------------------------------------------
    event Staked(address indexed user, uint256 amount, uint256 newBalance, uint256 lockEnd);
    event UnstakeRequested(address indexed user, uint256 amount, uint256 readyAt);
    event Withdrawn(address indexed user, uint256 amount);
    event Unstaked(address indexed user, uint256 amount);
    event RewardsHarvested(address indexed user, uint256 rewards, uint256 fromEpoch, uint256 toEpoch);
    event EpochDurationUpdated(uint256 newDuration);
    event MerkleRootUpdated(bytes32 newRoot);
    event CooldownUpdated(uint256 cooldownPeriod);
    event LockPeriodUpdated(uint256 lockPeriod);
    event RewardsDistributorUpdated(address rewardsDistributor);
    event EpochRewardAdded(uint256 indexed epochId, uint256 amount);

    // --------------------------------------------------
    // Errors
    // --------------------------------------------------

    error InvalidProof();
    error ZeroAmount();
    error LockActive();
    error NothingPending();
    error CooldownNotFinished();
    error NotAuthorized();
    error InsufficientBalance();

    // --------------------------------------------------
    // Construction
    // --------------------------------------------------
    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() Ownable(msg.sender) {
        _disableInitializers();
    }

    function initialize(
        bytes32 _merkleRoot,
        uint256 _lockPeriod,
        uint256 _cooldownPeriod,
        uint256 _epochDuration,
        address _owner
    ) public initializer {
        _transferOwnership(_owner);
        merkleRoot = _merkleRoot;
        lockPeriod = _lockPeriod;
        cooldownPeriod = _cooldownPeriod;
        epochDuration = _epochDuration;
    }

    // --------------------------------------------------
    // View functions - simple calculations
    // --------------------------------------------------
    function currentEpoch() public view returns (uint256) {
        if (genesisEpoch == 0) return 0;
        return (block.number - genesisEpoch) / epochDuration + 1;
    }

    function calculateEpochRewards(address _user, uint256 _epochId) public view returns (uint256 rewards) {
        if (epochToTotalStaked[_epochId] == 0) return 0;

        // Calculate user's stake at this specific epoch
        uint256 userStakeAtEpoch = _getUserStakeAtEpoch(_user, _epochId);

        rewards = (userStakeAtEpoch * epochRewards[_epochId]) / epochToTotalStaked[_epochId];
    }

    /// @notice Get user's staked amount at a specific epoch
    function _getUserStakeAtEpoch(address _user, uint256 _epochId) internal view returns (uint256) {
        UserStakeInfo storage userInfo = userStakeInfo[_user];

        // If user hasn't staked yet, return 0
        if (userInfo.lastStakedBlock == 0) return 0;

        // Check explicit epoch data first
        if (userInfo.epochToUserStakedAmount[_epochId] > 0) {
            return userInfo.epochToUserStakedAmount[_epochId];
        }

        // Calculate the epoch when user last staked
        uint256 userLastStakeEpoch = (userInfo.lastStakedBlock - genesisEpoch) / epochDuration + 1;

        // If user staked after this epoch, they have 0 stake
        if (userLastStakeEpoch > _epochId) return 0;

        // If user staked before or during this epoch, they had their current stake amount
        // This handles the case where epochs were backfilled
        return userInfo.stakedAmount;
    }

    // --------------------------------------------------
    // Admin configuration
    // --------------------------------------------------
    function setMerkleRoot(bytes32 _merkleRoot) external onlyOwner {
        merkleRoot = _merkleRoot;
        emit MerkleRootUpdated(_merkleRoot);
    }

    function setCooldown(uint256 _cooldown) external onlyOwner {
        cooldownPeriod = _cooldown;
        emit CooldownUpdated(_cooldown);
    }

    function setCooldownInEpochs(uint256 _epochs) external onlyOwner {
        cooldownPeriod = _epochs * epochDuration;
        emit CooldownUpdated(cooldownPeriod);
    }

    function setLockPeriod(uint256 _lockPeriod) external onlyOwner {
        lockPeriod = _lockPeriod;
        emit LockPeriodUpdated(_lockPeriod);
    }

    function setEpochDuration(uint256 _epochDuration) external onlyOwner {
        epochDuration = _epochDuration;
        emit EpochDurationUpdated(_epochDuration);
    }

    function setRewardsDistributor(address _distributor) external onlyOwner {
        rewardsDistributor = _distributor;
        emit RewardsDistributorUpdated(_distributor);
    }

    // --------------------------------------------------
    // Staking logic (with integrated whitelist validation)
    // --------------------------------------------------

    /// @notice Initialize staking (must be called before users can stake)
    function initializeStaking() external onlyOwner {
        require(genesisEpoch == 0, "Already initialized");
        genesisEpoch = block.number;
    }

    /// @notice Stake native PC with Merkle proof validation. Users must have valid migration proof to stake.
    function stake(bytes32[] calldata proof, uint256 migrationAmount, uint256 migrationEpoch)
        external
        payable
        nonReentrant
    {
        require(genesisEpoch != 0, "Not initialized");
        uint256 amount = msg.value;
        if (amount == 0) revert ZeroAmount();

        UserStakeInfo storage userInfo = userStakeInfo[msg.sender];

        // Only validate Merkle proof if user is not already registered
        if (!userInfo.isRegistered) {
            // Validate migration proof (migrationEpoch is just for uniqueness, amount doesn't matter for staking)
            bytes32 leaf = keccak256(abi.encodePacked(msg.sender, amount, migrationEpoch));
            bool valid = MerkleProof.verifyCalldata(proof, merkleRoot, leaf);
            if (!valid) revert InvalidProof();

            // Mark user as registered
            userInfo.isRegistered = true;
        }

        // Update user stake and epoch tracking
        _updateUserStakeForEpoch(msg.sender, amount);

        // Update lock - extends lock period
        lockEndBlock[msg.sender] = block.number + lockPeriod;

        emit Staked(msg.sender, amount, userInfo.stakedAmount, lockEndBlock[msg.sender]);
    }

    /// @notice Internal function to update user stake for current epoch
    function _updateUserStakeForEpoch(address _user, uint256 _amount) internal {
        uint256 currentEpochId = currentEpoch();
        UserStakeInfo storage userInfo = userStakeInfo[_user];

        // Store the old staked amount before updating
        uint256 oldStakedAmount = userInfo.stakedAmount;

        // Update user's total staked amount
        userInfo.stakedAmount += _amount;
        totalStaked += _amount;

        // Get the epoch when user last staked
        uint256 lastStakedEpoch =
            userInfo.lastStakedBlock == 0 ? 0 : (userInfo.lastStakedBlock - genesisEpoch) / epochDuration + 1;

        if (lastStakedEpoch == 0 || lastStakedEpoch == currentEpochId) {
            // First time staking OR staking again in same epoch - only update current epoch
            userInfo.epochToUserStakedAmount[currentEpochId] += _amount;
        } else {
            // Staking in different epoch - need to backfill missing epochs with old amount
            for (uint256 i = lastStakedEpoch + 1; i < currentEpochId; i++) {
                // For epochs between last stake and current, user had old amount
                if (userInfo.epochToUserStakedAmount[i] == 0) {
                    userInfo.epochToUserStakedAmount[i] = oldStakedAmount;
                }
            }
            // For current epoch, add the new amount
            userInfo.epochToUserStakedAmount[currentEpochId] += _amount;
        }

        // Update epoch total staked with proper backfilling
        _updateEpochTotalStaked(_amount, currentEpochId);

        userInfo.lastStakedBlock = block.number;
        if (userInfo.lastClaimedBlock == 0) {
            userInfo.lastClaimedBlock = block.number;
        }
    }

    // ✅ REMOVED: Expensive loop-based total calculation
    // Now using efficient incremental updates like PushCoreV2

    /// @notice Internal function to update epoch total staked (simple PushCoreV2 approach)
    function _updateEpochTotalStaked(uint256 _amount, uint256 _currentEpoch) internal {
        // For the current epoch, we need to calculate the total stake from all users
        // This is a simplified approach - in production you might want to optimize this

        // If this is the first time updating this epoch, initialize it
        if (epochToTotalStaked[_currentEpoch] == 0) {
            // Find the previous epoch total to backfill
            uint256 previousTotal = 0;
            for (uint256 i = _currentEpoch - 1; i >= 1; i--) {
                if (epochToTotalStaked[i] > 0) {
                    previousTotal = epochToTotalStaked[i];
                    break;
                }
            }

            // Backfill intermediate epochs with the previous total
            for (uint256 i = 1; i < _currentEpoch; i++) {
                if (epochToTotalStaked[i] == 0) {
                    epochToTotalStaked[i] = previousTotal;
                }
            }

            // Set current epoch to previous total + new amount
            epochToTotalStaked[_currentEpoch] = previousTotal + _amount;
        } else {
            // Epoch already has a total, just add the new amount
            epochToTotalStaked[_currentEpoch] += _amount;
        }
    }

    /// @notice Internal function to update epoch total staked during unstaking
    function _updateEpochTotalStakedForUnstake(uint256 _amount, uint256 _currentEpoch) internal {
        // Simply subtract the amount from the current epoch total
        if (epochToTotalStaked[_currentEpoch] >= _amount) {
            epochToTotalStaked[_currentEpoch] -= _amount;
        } else {
            epochToTotalStaked[_currentEpoch] = 0;
        }
    }

    /// @notice Request an unstake which starts a cooldown
    function requestUnstake(uint256 amount) external nonReentrant {
        if (amount == 0) revert ZeroAmount();
        if (block.number < lockEndBlock[msg.sender]) revert LockActive();

        UserStakeInfo storage userInfo = userStakeInfo[msg.sender];
        if (amount > userInfo.stakedAmount) revert InsufficientBalance();

        // Get current epoch for user's epoch-specific tracking
        uint256 currentEpochId = currentEpoch();

        // Update user's epoch-specific stake for current epoch
        userInfo.epochToUserStakedAmount[currentEpochId] = userInfo.stakedAmount - amount;

        // Move from active balance to pending withdrawal
        userInfo.stakedAmount -= amount;
        totalStaked -= amount;

        // Update epoch total staked when unstaking
        _updateEpochTotalStakedForUnstake(amount, currentEpochId);

        pendingWithdrawalAmount[msg.sender] += amount;
        uint256 readyAtBlock = block.number + cooldownPeriod;
        //TODO Do we need seperate withdrawal ready at block for each request?
        if (readyAtBlock < withdrawalReadyAtBlock[msg.sender]) {
            readyAtBlock = withdrawalReadyAtBlock[msg.sender];
        }
        withdrawalReadyAtBlock[msg.sender] = readyAtBlock;
        emit UnstakeRequested(msg.sender, amount, readyAtBlock);
    }

    /// @notice Withdraw tokens after the cooldown has passed. No time window restriction (can withdraw any time after readyAt).
    function withdraw() external nonReentrant {
        uint256 amount = pendingWithdrawalAmount[msg.sender];
        if (amount == 0) revert NothingPending();
        if (block.number < withdrawalReadyAtBlock[msg.sender]) {
            revert CooldownNotFinished();
        }

        pendingWithdrawalAmount[msg.sender] = 0;
        withdrawalReadyAtBlock[msg.sender] = 0;
        (bool ok,) = payable(msg.sender).call{value: amount}("");
        require(ok, "ETHTransferFailed");
        emit Withdrawn(msg.sender, amount);
    }

    /// @notice Harvest rewards from completed epochs
    function harvestRewards() public {
        uint256 currentEpochId = currentEpoch();
        // Only harvest if there are completed epochs
        if (currentEpochId <= 1) return;

        uint256 rewards = harvest(msg.sender, currentEpochId - 1);
        if (rewards > 0) {
            (bool ok,) = payable(msg.sender).call{value: rewards}("");
            require(ok, "ETHTransferFailed");
        }
    }

    /// @notice Internal harvest function - like PushCoreV2
    function harvest(address _user, uint256 _tillEpoch) internal returns (uint256 rewards) {
        UserStakeInfo storage userInfo = userStakeInfo[_user];

        uint256 currentEpochId = currentEpoch();
        uint256 nextFromEpoch;

        if (userInfo.lastClaimedBlock == 0) {
            // User hasn't claimed any rewards yet, start from epoch 1
            nextFromEpoch = 1;
        } else {
            nextFromEpoch = (userInfo.lastClaimedBlock - genesisEpoch) / epochDuration + 1;
        }

        require(currentEpochId > _tillEpoch, "Invalid tillEpoch"); //TODO Is this needed?
        require(_tillEpoch >= nextFromEpoch, "Invalid epoch range");

        for (uint256 i = nextFromEpoch; i <= _tillEpoch; i++) {
            uint256 epochReward = calculateEpochRewards(_user, i);
            rewards += epochReward;
        }

        usersRewardsClaimed[_user] += rewards;
        userInfo.lastClaimedBlock = genesisEpoch + _tillEpoch * epochDuration;

        emit RewardsHarvested(_user, rewards, nextFromEpoch, _tillEpoch);
    }

    //TODO Do we need a check to ensure the rewards are only for the current epoch?
    // --------------------------------------------------
    // Funding rewards - admin adds rewards per epoch like PushCoreV2
    // --------------------------------------------------
    /// @notice Add rewards for a specific epoch
    function addEpochReward(uint256 _epochId) external payable onlyOwner {
        require(genesisEpoch != 0, "Not initialized");
        uint256 amount = msg.value;
        if (amount == 0) revert ZeroAmount();
        epochRewards[_epochId] += amount;
        emit EpochRewardAdded(_epochId, amount);
    }

    /// @notice Add rewards for current epoch
    function addCurrentEpochReward() external payable {
        require(msg.sender == owner() || msg.sender == rewardsDistributor, "Not authorized");
        require(genesisEpoch != 0, "Not initialized");
        uint256 amount = msg.value;
        if (amount == 0) revert ZeroAmount();

        uint256 currentEpochId = currentEpoch();
        epochRewards[currentEpochId] += amount;
        emit EpochRewardAdded(currentEpochId, amount);
    }

    // --------------------------------------------------
    // Emergency admin ops
    // --------------------------------------------------
    /// @notice Recover ERC20 tokens accidentally sent to this contract (no effect on native balances).
    function recoverERC20(address token, uint256 amount) external onlyOwner {
        IERC20(token).transfer(owner(), amount);
    }

    /// @notice Allow the contract to receive ETH
    receive() external payable {}
}
