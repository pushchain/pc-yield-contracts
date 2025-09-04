// SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

import {IERC20} from "@openzeppelin-v5/contracts/token/ERC20/IERC20.sol";
import {Ownable} from "@openzeppelin-v5/contracts/access/Ownable.sol";
import {ReentrancyGuard} from "@openzeppelin-v5/contracts/utils/ReentrancyGuard.sol";
import {MerkleProof} from "@openzeppelin-v5/contracts/utils/cryptography/MerkleProof.sol";
import {Initializable} from "@openzeppelin-v5/contracts/proxy/utils/Initializable.sol";

/// @title RewardSeasonsYieldFarm
/// @notice Staking program for users involved in Reward Seasons with multiplier-based rewards.
/// @dev Features: 3-month lock, 7-day cooldown, multiplier-based rewards, whitelisted entry.
/// @dev Transparent upgradeable contract using TransparentUpgradeableProxy pattern.
/// @dev Whitelist validation using (recipient, multiplierPoints) Merkle tree.
/// @dev Note: This contract is designed for iterative deployment for each new reward season.
contract RewardSeasonsYieldFarm is Ownable, ReentrancyGuard, Initializable {
    // --------------------------------------------------
    // Program configuration
    // --------------------------------------------------
    // Staking and rewards are in native PC (payable)
    bytes32 public merkleRoot; // whitelist proof: keccak256(abi.encodePacked(recipient, multiplierPoints))
    uint256 public lockPeriod; // 3 months (in seconds)
    uint256 public cooldownPeriod; // 7 days (in seconds) - updateable

    // Season configuration
    uint256 public seasonStartTime; // timestamp when staking started
    uint256 public seasonEndTime; // timestamp when staking ends (3 months)
    bool public seasonActive; // whether the season is currently active

    // Reward configuration
    uint256 public totalRewards; // total rewards for the season
    uint256 public totalStaked; // total staked by all users
    uint256 public totalEffectiveStake; // sum of user.effectiveStake (staked * multiplier)

    address public rewardsDistributor; // optional role allowed to fund the season

    // Season snapshot for final reward calculation
    uint256 public seasonSnapshotTotalRewards;
    uint256 public seasonSnapshotTotalEffectiveStake;
    bool public seasonFinalized;

    // --------------------------------------------------
    // Staking state
    // --------------------------------------------------
    // User staking info
    struct UserStakeInfo {
        uint256 stakedAmount;
        uint256 multiplierPoints;
        uint256 lastStakedTime;
        bool isRegistered; // Track if user has been validated with Merkle proof
        uint256 effectiveStake; // stakedAmount * multiplierPoints
    }

    mapping(address => UserStakeInfo) public userStakeInfo;
    mapping(address => uint256) public usersRewardsClaimed;

    // Lock end per user (no unstake allowed before this timestamp)
    mapping(address => uint256) public lockEndTime;

    // Cooldown withdrawal state (single pending request model)
    mapping(address => uint256) public pendingWithdrawalAmount;
    mapping(address => uint256) public withdrawalReadyAtTime;

    // --------------------------------------------------
    // Events
    // --------------------------------------------------
    event Staked(
        address indexed user,
        uint256 amount,
        uint256 multiplierPoints,
        uint256 effectiveStake,
        uint256 lockEnd
    );
    event UnstakeRequested(
        address indexed user,
        uint256 amount,
        uint256 readyAt
    );
    event Withdrawn(address indexed user, uint256 amount);
    event Unstaked(address indexed user, uint256 amount);
    event RewardsHarvested(address indexed user, uint256 rewards);
    event SeasonEnded(uint256 totalRewards, uint256 totalEffectiveStake);

    event CooldownUpdated(uint256 cooldownPeriod);
    event LockPeriodUpdated(uint256 lockPeriod);
    event RewardsDistributorUpdated(address rewardsDistributor);
    event MerkleRootUpdated(bytes32 newRoot);

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
    error SeasonNotActive();
    error SeasonAlreadyEnded();
    error InvalidMultiplier();

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
        address _owner
    ) public initializer {
        _transferOwnership(_owner);
        merkleRoot = _merkleRoot;
        lockPeriod = _lockPeriod;
        cooldownPeriod = _cooldownPeriod;

        // Automatically start the season for this deployment
        seasonStartTime = block.timestamp;
        seasonEndTime = block.timestamp + _lockPeriod;
        seasonActive = true;
    }

    function calculateUserRewards(address _user) public view returns (uint256) {
        if (!seasonFinalized) return 0;
        if (
            seasonSnapshotTotalEffectiveStake == 0 ||
            seasonSnapshotTotalRewards == 0
        ) return 0;

        UserStakeInfo storage userInfo = userStakeInfo[_user];
        if (userInfo.effectiveStake == 0) return 0;

        uint256 entitled = (userInfo.effectiveStake *
            seasonSnapshotTotalRewards) / seasonSnapshotTotalEffectiveStake;
        uint256 claimed = usersRewardsClaimed[_user];
        if (entitled <= claimed) return 0;
        return entitled - claimed;
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

    function setLockPeriod(uint256 _lockPeriod) external onlyOwner {
        lockPeriod = _lockPeriod;
        emit LockPeriodUpdated(_lockPeriod);
    }

    function setRewardsDistributor(address _distributor) external onlyOwner {
        rewardsDistributor = _distributor;
        emit RewardsDistributorUpdated(_distributor);
    }

    // --------------------------------------------------
    // Season management
    // --------------------------------------------------
    function endSeason() external onlyOwner {
        require(seasonActive, "Season not active");
        require(block.timestamp >= seasonEndTime, "Season not ended");

        // Snapshot totals for final reward calculation
        seasonSnapshotTotalRewards = totalRewards;
        seasonSnapshotTotalEffectiveStake = totalEffectiveStake;
        seasonActive = false;
        seasonFinalized = true;

        emit SeasonEnded(
            seasonSnapshotTotalRewards,
            seasonSnapshotTotalEffectiveStake
        );
    }

    // --------------------------------------------------
    // Staking logic
    // --------------------------------------------------
    /// @notice Stake native PC with Merkle proof validation and multiplier points
    function stake(
        bytes32[] calldata proof,
        uint256 multiplierPoints
    ) external payable nonReentrant {
        require(seasonActive, "Season not active");
        require(block.timestamp < seasonEndTime, "Season ended");

        uint256 amount = msg.value;
        if (amount == 0) revert ZeroAmount();
        if (multiplierPoints == 0) revert InvalidMultiplier();

        UserStakeInfo storage userInfo = userStakeInfo[msg.sender];

        // Verify Merkle proof when registering OR when multiplierPoints differs
        if (
            !userInfo.isRegistered ||
            userInfo.multiplierPoints != multiplierPoints
        ) {
            bytes32 leaf = keccak256(
                abi.encodePacked(msg.sender, multiplierPoints)
            );
            if (!MerkleProof.verify(proof, merkleRoot, leaf)) {
                revert InvalidProof();
            }
            // Only mark registered if proof passes
            userInfo.isRegistered = true;
        }

        // Remove old effective stake from totals if user was already registered
        uint256 oldEffective = userInfo.effectiveStake;
        if (oldEffective > 0) {
            totalEffectiveStake -= oldEffective;
        }

        // Update stake info
        userInfo.stakedAmount += amount;
        userInfo.multiplierPoints = multiplierPoints;
        userInfo.effectiveStake =
            userInfo.stakedAmount *
            userInfo.multiplierPoints;
        userInfo.lastStakedTime = block.timestamp;

        // Set lock end time to season end (force full season)
        lockEndTime[msg.sender] = seasonEndTime;

        // Update totals
        totalStaked += amount;
        totalEffectiveStake += userInfo.effectiveStake;

        emit Staked(
            msg.sender,
            amount,
            multiplierPoints,
            userInfo.effectiveStake,
            lockEndTime[msg.sender]
        );
    }

    // --------------------------------------------------
    // Unstaking and withdrawal logic
    // --------------------------------------------------
    /// @notice Unstake and harvest rewards in a single transaction (after season ends)
    function unstakeAndHarvest(uint256 amount) external nonReentrant {
        require(seasonFinalized, "Season not finalized");

        // First: Harvest any unclaimed rewards using existing function
        uint256 userRewards = calculateUserRewards(msg.sender);
        if (userRewards > 0) {
            // Update claimed rewards
            usersRewardsClaimed[msg.sender] += userRewards;

            // Transfer rewards immediately
            (bool success, ) = msg.sender.call{value: userRewards}("");
            require(success, "Reward transfer failed");

            emit RewardsHarvested(msg.sender, userRewards);
        }

        // Then: Use existing requestUnstake logic by calling it directly
        requestUnstake(amount);
    }

    /// @notice Request unstaking (starts cooldown period)
    function requestUnstake(uint256 amount) public {
        UserStakeInfo storage userInfo = userStakeInfo[msg.sender];
        require(userInfo.isRegistered, "User not registered");
        require(amount > 0, "Amount must be greater than 0");
        require(amount <= userInfo.stakedAmount, "Insufficient staked amount");
        require(
            block.timestamp >= lockEndTime[msg.sender],
            "Lock period not ended"
        );
        require(
            pendingWithdrawalAmount[msg.sender] == 0,
            "Withdrawal already pending"
        );

        // Calculate new effective stake
        uint256 newStakedAmount = userInfo.stakedAmount - amount;
        uint256 newEffectiveStake = newStakedAmount * userInfo.multiplierPoints;

        // Update totals
        totalStaked -= amount;
        totalEffectiveStake =
            totalEffectiveStake -
            userInfo.effectiveStake +
            newEffectiveStake;

        // Update user info
        userInfo.stakedAmount = newStakedAmount;
        userInfo.effectiveStake = newEffectiveStake;

        // If user unstaked everything, mark as unregistered
        if (newStakedAmount == 0) {
            userInfo.isRegistered = false;
            delete lockEndTime[msg.sender];
        }

        // Set cooldown
        pendingWithdrawalAmount[msg.sender] = amount;
        withdrawalReadyAtTime[msg.sender] = block.timestamp + cooldownPeriod;

        emit UnstakeRequested(
            msg.sender,
            amount,
            withdrawalReadyAtTime[msg.sender]
        );
    }

    /// @notice Withdraw after cooldown period
    function withdraw() external nonReentrant {
        uint256 amount = pendingWithdrawalAmount[msg.sender];
        if (amount == 0) revert NothingPending();
        if (block.timestamp < withdrawalReadyAtTime[msg.sender])
            revert CooldownNotFinished();

        // Clear pending withdrawal
        delete pendingWithdrawalAmount[msg.sender];
        delete withdrawalReadyAtTime[msg.sender];

        // Transfer tokens
        (bool success, ) = msg.sender.call{value: amount}("");
        require(success, "Transfer failed");

        emit Withdrawn(msg.sender, amount);
    }

    // --------------------------------------------------
    // Rewards logic
    // --------------------------------------------------
    /// @notice Add rewards to the season (only owner or rewards distributor)
    function addRewards() external payable {
        require(
            msg.sender == owner() || msg.sender == rewardsDistributor,
            "Not authorized"
        );
        require(msg.value > 0, "No rewards provided");
        require(seasonActive, "Season not active");

        totalRewards += msg.value;
    }

    /// @notice Harvest rewards for the user
    function harvestRewards() external nonReentrant {
        require(seasonFinalized, "Season not finalized");
        UserStakeInfo storage userInfo = userStakeInfo[msg.sender];
        require(userInfo.isRegistered, "User not registered");

        uint256 userRewards = calculateUserRewards(msg.sender);
        require(userRewards > 0, "No rewards to harvest");

        // Update claimed rewards
        usersRewardsClaimed[msg.sender] += userRewards;

        // Transfer rewards
        (bool success, ) = msg.sender.call{value: userRewards}("");
        require(success, "Transfer failed");

        emit RewardsHarvested(msg.sender, userRewards);
    }

    // --------------------------------------------------
    // Emergency functions
    // --------------------------------------------------
    /// @notice Emergency function to recover stuck ERC20 tokens
    function recoverERC20(address token, uint256 amount) external onlyOwner {
        IERC20(token).transfer(owner(), amount);
    }

    /// @notice Emergency function to recover stuck native tokens (only if season ended)
    function recoverNative() external onlyOwner {
        require(!seasonActive, "Season still active");
        require(
            block.timestamp > seasonEndTime + 30 days,
            "Must wait 30 days after season end"
        );

        uint256 balance = address(this).balance;
        require(balance > 0, "No balance to recover");

        (bool success, ) = owner().call{value: balance}("");
        require(success, "Transfer failed");
    }

    // --------------------------------------------------
    // Receive function
    // --------------------------------------------------
    receive() external payable {
        // Allow receiving native tokens for rewards
    }
}
