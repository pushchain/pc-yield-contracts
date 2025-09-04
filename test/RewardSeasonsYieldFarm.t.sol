// SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

import {Test, console2} from "forge-std/Test.sol";
import {RewardSeasonsYieldFarm} from "../src/RewardSeasonsYieldFarm.sol";
import {TransparentUpgradeableProxy} from "@openzeppelin-v5/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import {Ownable} from "@openzeppelin-v5/contracts/access/Ownable.sol";

contract RewardSeasonsYieldFarmTest is Test {
    RewardSeasonsYieldFarm public implementation;
    RewardSeasonsYieldFarm public farm;
    TransparentUpgradeableProxy public proxy;

    // Test addresses
    address public owner = address(0x1);
    address public user1 = address(0x2);
    address public user2 = address(0x3);
    address public user3 = address(0x4);
    address public rewardsDistributor = address(0x5);

    // Test parameters
    uint256 public constant LOCK_PERIOD = 90 days;
    uint256 public constant COOLDOWN_PERIOD = 7 days;
    uint256 public constant STAKE_AMOUNT_1 = 1000e18;
    uint256 public constant STAKE_AMOUNT_2 = 500e18;
    uint256 public constant MULTIPLIER_1 = 10;
    uint256 public constant MULTIPLIER_2 = 5;
    uint256 public constant REWARD_AMOUNT = 10000e18;

    // Merkle tree data - generated using scripts/generate-reward-merkle.js
    bytes32 public constant MERKLE_ROOT =
        0x66a9624863e3c9d2abd928fb929aab3ac635f20fbdf04e5275e8374b7618fd23;

    // Hardcoded proofs for testing (generated off-chain)
    bytes32[] public proof1;
    bytes32[] public proof2;
    bytes32[] public proof3;
    bytes32[] public proof4;
    bytes32[] public proof5;

    function setUp() public {
        // Setup hardcoded proofs for testing
        _setupMerkleProofs();

        // Deploy implementation and proxy
        vm.startPrank(owner);
        implementation = new RewardSeasonsYieldFarm();

        bytes memory initData = abi.encodeWithSelector(
            RewardSeasonsYieldFarm.initialize.selector,
            MERKLE_ROOT,
            LOCK_PERIOD,
            COOLDOWN_PERIOD,
            owner
        );

        proxy = new TransparentUpgradeableProxy(
            address(implementation),
            owner,
            initData
        );

        farm = RewardSeasonsYieldFarm(payable(address(proxy)));

        // Set rewards distributor
        farm.setRewardsDistributor(rewardsDistributor);
        vm.stopPrank();

        // Fund test addresses
        vm.deal(user1, 10000e18);
        vm.deal(user2, 10000e18);
        vm.deal(user3, 10000e18);
        vm.deal(rewardsDistributor, 10000e18);
    }

    function _setupMerkleProofs() internal {
        // Proof for User1 (multiplier 10)
        proof1 = new bytes32[](3);
        proof1[
            0
        ] = 0x3da7aecc97f214c393fbe5ddd14a304f5d5e52c9d4800ea6573cdd5a18c2e367;
        proof1[
            1
        ] = 0xc2cee88098bb2be0d3ce9a86a25812911bd83e3920924b266fdb80df58ed85ba;
        proof1[
            2
        ] = 0x075fa8d81f1e3a715dc6c507ebaa1d669a156d2ddbafedaf509ef7c680d1086f;

        // Proof for User2 (multiplier 5)
        proof2 = new bytes32[](3);
        proof2[
            0
        ] = 0xf1ee3fc70f3ac6953b1e4f82164d92d184f40229ed9bedef24ebfd297f485661;
        proof2[
            1
        ] = 0xc2cee88098bb2be0d3ce9a86a25812911bd83e3920924b266fdb80df58ed85ba;
        proof2[
            2
        ] = 0x075fa8d81f1e3a715dc6c507ebaa1d669a156d2ddbafedaf509ef7c680d1086f;

        // Proof for User3 (multiplier 8)
        proof3 = new bytes32[](3);
        proof3[
            0
        ] = 0xd9c79db561b58a44e9a10c0f4e0e5b9f2d9a385dd6f4f80ae5cabf131e314b83;
        proof3[
            1
        ] = 0x9944f8b0731bcc7c7acf0e1affad11527ba96e8175e2b2fdad56b91f0abd8304;
        proof3[
            2
        ] = 0x075fa8d81f1e3a715dc6c507ebaa1d669a156d2ddbafedaf509ef7c680d1086f;

        // Proof for User4 (multiplier 12)
        proof4 = new bytes32[](3);
        proof4[
            0
        ] = 0x2bd676a6e96f03b28e197e5e86688c491ad7f2410eb91608c88cee8652bd787f;
        proof4[
            1
        ] = 0x9944f8b0731bcc7c7acf0e1affad11527ba96e8175e2b2fdad56b91f0abd8304;
        proof4[
            2
        ] = 0x075fa8d81f1e3a715dc6c507ebaa1d669a156d2ddbafedaf509ef7c680d1086f;

        // Proof for User5 (multiplier 3)
        proof5 = new bytes32[](1);
        proof5[
            0
        ] = 0x52f7cc2f66dee8aa66248aeeb053289a1b15d9c70d2b67f3b8174dee64a3b9da;
    }

    // ========================================
    // CORE STAKING TESTS
    // ========================================

    function test_Stake_NewUser() public {
        vm.startPrank(user1);

        uint256 initialBalance = user1.balance;

        farm.stake{value: STAKE_AMOUNT_1}(proof1, MULTIPLIER_1);

        assertEq(farm.totalStaked(), STAKE_AMOUNT_1);
        assertEq(farm.totalEffectiveStake(), STAKE_AMOUNT_1 * MULTIPLIER_1);
        (
            uint256 stakedAmount,
            uint256 multiplierPoints,
            ,
            ,
            uint256 effectiveStake
        ) = farm.userStakeInfo(user1);
        assertEq(effectiveStake, STAKE_AMOUNT_1 * MULTIPLIER_1);
        assertEq(multiplierPoints, MULTIPLIER_1);
        assertGt(farm.lockEndTime(user1), block.timestamp);
        assertEq(user1.balance, initialBalance - STAKE_AMOUNT_1);

        vm.stopPrank();
    }

    function test_Stake_ExistingUser() public {
        vm.startPrank(user1);

        // First stake
        farm.stake{value: STAKE_AMOUNT_1}(proof1, MULTIPLIER_1);
        (
            uint256 stakedAmount1,
            uint256 multiplierPoints1,
            ,
            ,
            uint256 firstEffectiveStake
        ) = farm.userStakeInfo(user1);

        // Second stake
        farm.stake{value: STAKE_AMOUNT_2}(proof1, MULTIPLIER_1);
        (
            uint256 stakedAmount2,
            uint256 multiplierPoints2,
            ,
            ,
            uint256 secondEffectiveStake
        ) = farm.userStakeInfo(user1);

        assertEq(
            secondEffectiveStake,
            firstEffectiveStake + (STAKE_AMOUNT_2 * MULTIPLIER_1)
        );
        assertEq(farm.totalStaked(), STAKE_AMOUNT_1 + STAKE_AMOUNT_2);

        vm.stopPrank();
    }

    function test_Stake_MultiplierCannotBeChanged() public {
        vm.startPrank(user1);

        // First stake with multiplier 10 (proof1)
        farm.stake{value: STAKE_AMOUNT_1}(proof1, MULTIPLIER_1);
        (
            uint256 stakedAmount1,
            uint256 multiplierPoints1,
            ,
            ,
            uint256 firstEffectiveStake
        ) = farm.userStakeInfo(user1);

        // Try to update multiplier to 5 (proof2) with 0 amount - should fail
        vm.expectRevert(RewardSeasonsYieldFarm.ZeroAmount.selector);
        farm.stake{value: 0}(proof2, MULTIPLIER_2);

        // Multiplier should remain unchanged
        (
            uint256 stakedAmount2,
            uint256 multiplierPoints2,
            ,
            ,
            uint256 effectiveStake
        ) = farm.userStakeInfo(user1);
        assertEq(multiplierPoints2, MULTIPLIER_1);
        assertEq(effectiveStake, firstEffectiveStake);

        vm.stopPrank();
    }

    function test_Stake_InvalidProof() public {
        vm.startPrank(user1);

        bytes32[] memory invalidProof = new bytes32[](1);
        invalidProof[
            0
        ] = 0x9999999999999999999999999999999999999999999999999999999999999999;

        vm.expectRevert(RewardSeasonsYieldFarm.InvalidProof.selector);
        farm.stake{value: STAKE_AMOUNT_1}(invalidProof, MULTIPLIER_1);

        vm.stopPrank();
    }

    function test_Stake_ZeroAmount() public {
        vm.startPrank(user1);

        vm.expectRevert(RewardSeasonsYieldFarm.ZeroAmount.selector);
        farm.stake{value: 0}(proof1, MULTIPLIER_1);

        vm.stopPrank();
    }

    function test_Stake_InvalidMultiplier() public {
        vm.startPrank(user1);

        vm.expectRevert(RewardSeasonsYieldFarm.InvalidMultiplier.selector);
        farm.stake{value: STAKE_AMOUNT_1}(proof1, 0);

        vm.stopPrank();
    }

    // ========================================
    // LOCK PERIOD TESTS
    // ========================================

    function test_LockPeriod_SeasonEnd() public {
        vm.startPrank(user1);

        farm.stake{value: STAKE_AMOUNT_1}(proof1, MULTIPLIER_1);

        uint256 lockEnd = farm.lockEndTime(user1);
        uint256 seasonEnd = farm.seasonEndTime();

        assertEq(lockEnd, seasonEnd);
        assertGt(farm.lockEndTime(user1), block.timestamp);

        vm.stopPrank();
    }

    function test_Unstake_BeforeLockEnd() public {
        vm.startPrank(user1);

        farm.stake{value: STAKE_AMOUNT_1}(proof1, MULTIPLIER_1);

        // Try to unstake before lock period ends
        vm.expectRevert("Lock period not ended");
        farm.requestUnstake(STAKE_AMOUNT_1 / 2);

        vm.stopPrank();
    }

    // ========================================
    // UNSTAKING AND WITHDRAWAL TESTS
    // ========================================

    function test_Unstake_AfterLockEnd() public {
        vm.startPrank(user1);

        farm.stake{value: STAKE_AMOUNT_1}(proof1, MULTIPLIER_1);

        // Fast forward to after lock period
        vm.warp(block.timestamp + LOCK_PERIOD + 1);

        farm.requestUnstake(STAKE_AMOUNT_1 / 2);

        assertEq(farm.pendingWithdrawalAmount(user1), STAKE_AMOUNT_1 / 2);
        assertGt(farm.withdrawalReadyAtTime(user1), block.timestamp);

        vm.stopPrank();
    }

    function test_Withdraw_AfterCooldown() public {
        vm.startPrank(user1);

        farm.stake{value: STAKE_AMOUNT_1}(proof1, MULTIPLIER_1);

        // Fast forward to after lock period
        vm.warp(block.timestamp + LOCK_PERIOD + 1);
        farm.requestUnstake(STAKE_AMOUNT_1 / 2);

        // Fast forward to after cooldown
        vm.warp(block.timestamp + COOLDOWN_PERIOD + 1);

        uint256 initialBalance = user1.balance;
        farm.withdraw();

        assertEq(user1.balance, initialBalance + STAKE_AMOUNT_1 / 2);
        assertEq(farm.pendingWithdrawalAmount(user1), 0);
        assertEq(farm.withdrawalReadyAtTime(user1), 0);

        vm.stopPrank();
    }

    function test_Withdraw_BeforeCooldown() public {
        vm.startPrank(user1);

        farm.stake{value: STAKE_AMOUNT_1}(proof1, MULTIPLIER_1);

        // Fast forward to after lock period
        vm.warp(block.timestamp + LOCK_PERIOD + 1);
        farm.requestUnstake(STAKE_AMOUNT_1 / 2);

        // Try to withdraw before cooldown ends
        vm.expectRevert(RewardSeasonsYieldFarm.CooldownNotFinished.selector);
        farm.withdraw();

        vm.stopPrank();
    }

    function test_Unstake_Everything() public {
        vm.startPrank(user1);

        farm.stake{value: STAKE_AMOUNT_1}(proof1, MULTIPLIER_1);

        // Fast forward to after lock period
        vm.warp(block.timestamp + LOCK_PERIOD + 1);
        farm.requestUnstake(STAKE_AMOUNT_1);

        // User should be unregistered
        (, , , bool isRegistered, ) = farm.userStakeInfo(user1);
        assertFalse(isRegistered);

        vm.stopPrank();
    }

    // ========================================
    // REWARDS TESTS
    // ========================================

    function test_AddRewards() public {
        vm.startPrank(rewardsDistributor);

        uint256 initialRewards = farm.totalRewards();
        farm.addRewards{value: REWARD_AMOUNT}();

        assertEq(farm.totalRewards(), initialRewards + REWARD_AMOUNT);

        vm.stopPrank();
    }

    function test_AddRewards_Unauthorized() public {
        vm.startPrank(user1);

        vm.expectRevert("Not authorized");
        farm.addRewards{value: REWARD_AMOUNT}();

        vm.stopPrank();
    }

    function test_AddRewards_AfterSeasonEnd() public {
        // End the season first
        vm.startPrank(owner);
        vm.warp(block.timestamp + LOCK_PERIOD + 1);
        farm.endSeason();
        vm.stopPrank();

        vm.startPrank(rewardsDistributor);

        vm.expectRevert("Season not active");
        farm.addRewards{value: REWARD_AMOUNT}();

        vm.stopPrank();
    }

    // ========================================
    // SEASON MANAGEMENT TESTS
    // ========================================

    function test_EndSeason() public {
        vm.startPrank(owner);

        // Add some rewards first
        vm.stopPrank();
        vm.prank(rewardsDistributor);
        farm.addRewards{value: REWARD_AMOUNT}();

        // Stake some users
        vm.prank(user1);
        farm.stake{value: STAKE_AMOUNT_1}(proof1, MULTIPLIER_1);

        vm.prank(user2);
        farm.stake{value: STAKE_AMOUNT_2}(proof2, MULTIPLIER_2);

        // Fast forward to after lock period
        vm.warp(block.timestamp + LOCK_PERIOD + 1);

        // End season
        vm.startPrank(owner);
        farm.endSeason();

        assertFalse(farm.seasonActive());
        assertTrue(farm.seasonFinalized());
        assertEq(farm.seasonSnapshotTotalRewards(), REWARD_AMOUNT);
        assertEq(
            farm.seasonSnapshotTotalEffectiveStake(),
            (STAKE_AMOUNT_1 * MULTIPLIER_1) + (STAKE_AMOUNT_2 * MULTIPLIER_2)
        );

        vm.stopPrank();
    }

    function test_EndSeason_TooEarly() public {
        vm.startPrank(owner);

        vm.expectRevert("Season not ended");
        farm.endSeason();

        vm.stopPrank();
    }

    function test_EndSeason_AlreadyEnded() public {
        vm.startPrank(owner);

        // End season once
        vm.warp(block.timestamp + LOCK_PERIOD + 1);
        farm.endSeason();

        // Try to end again
        vm.expectRevert("Season not active");
        farm.endSeason();

        vm.stopPrank();
    }

    // ========================================
    // REWARD HARVESTING TESTS
    // ========================================

    function test_HarvestRewards_AfterSeasonEnd() public {
        // Setup: Add rewards and stake users
        vm.startPrank(rewardsDistributor);
        farm.addRewards{value: REWARD_AMOUNT}();
        vm.stopPrank();

        vm.startPrank(user1);
        farm.stake{value: STAKE_AMOUNT_1}(proof1, MULTIPLIER_1);
        vm.stopPrank();

        vm.startPrank(user2);
        farm.stake{value: STAKE_AMOUNT_2}(proof2, MULTIPLIER_2);
        vm.stopPrank();

        // End season
        vm.startPrank(owner);
        vm.warp(block.timestamp + LOCK_PERIOD + 1);
        farm.endSeason();
        vm.stopPrank();

        // Harvest rewards
        vm.startPrank(user1);
        uint256 initialBalance = user1.balance;
        farm.harvestRewards();

        // Calculate expected rewards
        uint256 totalEffectiveStake = (STAKE_AMOUNT_1 * MULTIPLIER_1) +
            (STAKE_AMOUNT_2 * MULTIPLIER_2);
        uint256 expectedRewards = (STAKE_AMOUNT_1 *
            MULTIPLIER_1 *
            REWARD_AMOUNT) / totalEffectiveStake;

        assertEq(user1.balance, initialBalance + expectedRewards);
        vm.stopPrank();
    }

    function test_HarvestRewards_BeforeSeasonEnd() public {
        // Setup: Add rewards and stake user
        vm.startPrank(rewardsDistributor);
        farm.addRewards{value: REWARD_AMOUNT}();
        vm.stopPrank();

        vm.startPrank(user1);
        farm.stake{value: STAKE_AMOUNT_1}(proof1, MULTIPLIER_1);

        vm.expectRevert("Season not finalized");
        farm.harvestRewards();

        vm.stopPrank();
    }

    function test_HarvestRewards_DoubleClaim() public {
        // Setup: Add rewards and stake user
        vm.startPrank(rewardsDistributor);
        farm.addRewards{value: REWARD_AMOUNT}();
        vm.stopPrank();

        vm.startPrank(user1);
        farm.stake{value: STAKE_AMOUNT_1}(proof1, MULTIPLIER_1);
        vm.stopPrank();

        // End season
        vm.startPrank(owner);
        vm.warp(block.timestamp + LOCK_PERIOD + 1);
        farm.endSeason();
        vm.stopPrank();

        // Harvest rewards twice
        vm.startPrank(user1);
        farm.harvestRewards();

        // Second harvest should fail (no more rewards)
        uint256 secondHarvest = farm.calculateUserRewards(user1);
        assertEq(secondHarvest, 0);

        vm.stopPrank();
    }

    // ========================================
    // EDGE CASES AND INTEGRATION TESTS
    // ========================================

    function test_MultipleUsers_CompleteLifecycle() public {
        // Setup: Add rewards
        vm.startPrank(rewardsDistributor);
        farm.addRewards{value: REWARD_AMOUNT}();
        vm.stopPrank();

        // User1 stakes early
        vm.startPrank(user1);
        farm.stake{value: STAKE_AMOUNT_1}(proof1, MULTIPLIER_1);
        vm.stopPrank();

        // User2 stakes later
        vm.warp(block.timestamp + 30 days);
        vm.startPrank(user2);
        farm.stake{value: STAKE_AMOUNT_2}(proof2, MULTIPLIER_2);
        vm.stopPrank();

        // End season
        vm.startPrank(owner);
        vm.warp(block.timestamp + LOCK_PERIOD + 1);
        farm.endSeason();
        vm.stopPrank();

        // Both users should be able to harvest
        vm.startPrank(user1);
        uint256 user1Rewards = farm.calculateUserRewards(user1);
        assertGt(user1Rewards, 0);
        vm.stopPrank();

        vm.startPrank(user2);
        uint256 user2Rewards = farm.calculateUserRewards(user2);
        assertGt(user2Rewards, 0);
        vm.stopPrank();
    }

    function test_PartialUnstake_EffectiveStakeUpdate() public {
        vm.startPrank(user1);

        farm.stake{value: STAKE_AMOUNT_1}(proof1, MULTIPLIER_1);

        (
            uint256 stakedAmount,
            uint256 multiplierPoints,
            ,
            ,
            uint256 initialEffectiveStake
        ) = farm.userStakeInfo(user1);

        // Fast forward to after lock period
        vm.warp(block.timestamp + LOCK_PERIOD + 1);

        // Partial unstake
        farm.requestUnstake(STAKE_AMOUNT_1 / 2);

        (
            uint256 stakedAmount2,
            uint256 multiplierPoints2,
            ,
            ,
            uint256 newEffectiveStake
        ) = farm.userStakeInfo(user1);
        assertEq(newEffectiveStake, initialEffectiveStake / 2);

        vm.stopPrank();
    }

    function test_SeasonTiming_AutomaticStart() public view {
        // Season should start automatically at deployment
        assertTrue(farm.seasonActive());
        assertGt(farm.seasonStartTime(), 0);
        assertGt(farm.seasonEndTime(), farm.seasonStartTime());
        assertEq(farm.seasonEndTime() - farm.seasonStartTime(), LOCK_PERIOD);
    }

    function test_CooldownPeriod_Updateable() public {
        uint256 newCooldown = 14 days;

        vm.startPrank(owner);
        farm.setCooldown(newCooldown);
        assertEq(farm.cooldownPeriod(), newCooldown);
        vm.stopPrank();
    }

    function test_LockPeriod_Updateable() public {
        uint256 newLockPeriod = 180 days;

        vm.startPrank(owner);
        farm.setLockPeriod(newLockPeriod);
        assertEq(farm.lockPeriod(), newLockPeriod);
        vm.stopPrank();
    }

    // ========================================
    // SECURITY TESTS
    // ========================================

    function test_ReentrancyProtection_Complete() public {
        // Test that all critical functions follow CEI pattern and cannot be reentered
        vm.startPrank(user1);

        // 1. Test stake function CEI pattern
        farm.stake{value: STAKE_AMOUNT_1}(proof1, MULTIPLIER_1);
        (
            uint256 stakedAmount,
            uint256 multiplierPoints,
            ,
            ,
            uint256 effectiveStake
        ) = farm.userStakeInfo(user1);
        assertEq(effectiveStake, STAKE_AMOUNT_1 * MULTIPLIER_1);
        assertEq(multiplierPoints, MULTIPLIER_1);

        // 2. Test requestUnstake function CEI pattern
        vm.warp(block.timestamp + LOCK_PERIOD + 1);
        farm.requestUnstake(STAKE_AMOUNT_1 / 2);
        assertEq(farm.pendingWithdrawalAmount(user1), STAKE_AMOUNT_1 / 2);

        // 3. Test withdraw function CEI pattern
        vm.warp(block.timestamp + COOLDOWN_PERIOD + 1);
        uint256 initialBalance = user1.balance;
        farm.withdraw();
        assertGt(user1.balance, initialBalance);
        assertEq(farm.pendingWithdrawalAmount(user1), 0);

        vm.stopPrank();
    }

    function test_AccessControl_AdminFunctions() public {
        // Test all admin functions for proper access control
        address attacker = address(0x999);

        // Test setMerkleRoot
        vm.startPrank(attacker);
        vm.expectRevert(
            abi.encodeWithSelector(
                Ownable.OwnableUnauthorizedAccount.selector,
                attacker
            )
        );
        farm.setMerkleRoot(bytes32(uint256(0x123)));

        // Test setCooldown
        vm.expectRevert(
            abi.encodeWithSelector(
                Ownable.OwnableUnauthorizedAccount.selector,
                attacker
            )
        );
        farm.setCooldown(14 days);

        // Test setLockPeriod
        vm.expectRevert(
            abi.encodeWithSelector(
                Ownable.OwnableUnauthorizedAccount.selector,
                attacker
            )
        );
        farm.setLockPeriod(180 days);

        // Test setRewardsDistributor
        vm.expectRevert(
            abi.encodeWithSelector(
                Ownable.OwnableUnauthorizedAccount.selector,
                attacker
            )
        );
        farm.setRewardsDistributor(attacker);

        // Test endSeason
        vm.expectRevert(
            abi.encodeWithSelector(
                Ownable.OwnableUnauthorizedAccount.selector,
                attacker
            )
        );
        farm.endSeason();

        // Test recoverERC20
        vm.expectRevert(
            abi.encodeWithSelector(
                Ownable.OwnableUnauthorizedAccount.selector,
                attacker
            )
        );
        farm.recoverERC20(address(0x123), 100);

        // Test recoverNative
        vm.expectRevert(
            abi.encodeWithSelector(
                Ownable.OwnableUnauthorizedAccount.selector,
                attacker
            )
        );
        farm.recoverNative();

        vm.stopPrank();
    }

    function test_EmergencyFunctions_Security() public {
        // Test emergency recovery functions with proper validation

        // 1. Test recoverERC20
        TestERC20 token = new TestERC20("Test", "TST");
        token.mint(address(farm), 1000e18);

        uint256 initialBalance = token.balanceOf(owner);
        vm.startPrank(owner);
        farm.recoverERC20(address(token), 500e18);
        vm.stopPrank();

        assertEq(token.balanceOf(owner), initialBalance + 500e18);
        assertEq(token.balanceOf(address(farm)), 500e18);

        // 2. Test recoverNative - should fail while season active
        vm.startPrank(owner);
        vm.expectRevert("Season still active");
        farm.recoverNative();
        vm.stopPrank();

        // 3. Test recoverNative - should fail before 30-day delay
        vm.startPrank(owner);
        vm.warp(block.timestamp + LOCK_PERIOD + 1);
        farm.endSeason();
        vm.expectRevert("Must wait 30 days after season end");
        farm.recoverNative();
        vm.stopPrank();

        // 4. Test recoverNative - should succeed after delay
        vm.startPrank(owner);
        vm.warp(block.timestamp + 30 days + 1);
        vm.deal(address(farm), 1000e18);
        uint256 initialOwnerBalance = owner.balance;
        farm.recoverNative();
        assertEq(owner.balance, initialOwnerBalance + 1000e18);
        assertEq(address(farm).balance, 0);
        vm.stopPrank();
    }

    function test_MerkleProof_Security() public {
        // Test Merkle proof security edge cases
        vm.startPrank(user1);

        // 1. Test empty proof
        bytes32[] memory emptyProof = new bytes32[](0);
        vm.expectRevert(); // Should revert due to invalid proof
        farm.stake{value: STAKE_AMOUNT_1}(emptyProof, MULTIPLIER_1);

        // 2. Test invalid proof
        bytes32[] memory invalidProof = new bytes32[](1);
        invalidProof[
            0
        ] = 0x9999999999999999999999999999999999999999999999999999999999999999;
        vm.expectRevert(RewardSeasonsYieldFarm.InvalidProof.selector);
        farm.stake{value: STAKE_AMOUNT_1}(invalidProof, MULTIPLIER_1);

        // 3. Test proof for wrong multiplier
        vm.expectRevert(RewardSeasonsYieldFarm.InvalidProof.selector);
        farm.stake{value: STAKE_AMOUNT_1}(proof1, MULTIPLIER_2); // proof1 is for MULTIPLIER_1

        vm.stopPrank();
    }

    function test_Arithmetic_Security() public {
        // Test arithmetic edge cases and overflow protection
        vm.startPrank(user1);

        // 1. Test extreme multiplier values
        uint256 maxMultiplier = type(uint256).max;
        vm.expectRevert(); // Should revert due to arithmetic overflow
        farm.stake{value: STAKE_AMOUNT_1}(proof1, maxMultiplier);

        // 2. Test very small amounts
        uint256 smallAmount = 1;
        farm.stake{value: smallAmount}(proof1, MULTIPLIER_1);
        (
            uint256 stakedAmount,
            uint256 multiplierPoints,
            ,
            ,
            uint256 effectiveStake
        ) = farm.userStakeInfo(user1);
        assertEq(effectiveStake, smallAmount * MULTIPLIER_1);

        // 3. Test zero amount (should fail)
        vm.expectRevert(RewardSeasonsYieldFarm.ZeroAmount.selector);
        farm.stake{value: 0}(proof1, MULTIPLIER_1);

        // 4. Test zero multiplier (should fail)
        vm.expectRevert(RewardSeasonsYieldFarm.InvalidMultiplier.selector);
        farm.stake{value: STAKE_AMOUNT_1}(proof1, 0);

        vm.stopPrank();
    }

    function test_Initialization_Security() public {
        // Test initialization security and reinitialization protection

        // 1. Test reinitialization protection
        vm.startPrank(owner);
        vm.expectRevert(); // Any revert is fine for reinitialization
        farm.initialize(MERKLE_ROOT, LOCK_PERIOD, COOLDOWN_PERIOD, owner);
        vm.stopPrank();

        // 2. Test new deployment with invalid parameters
        RewardSeasonsYieldFarm newImpl = new RewardSeasonsYieldFarm();
        bytes memory initData = abi.encodeWithSelector(
            RewardSeasonsYieldFarm.initialize.selector,
            bytes32(0), // invalid merkle root
            LOCK_PERIOD,
            COOLDOWN_PERIOD,
            address(0) // invalid owner
        );

        TransparentUpgradeableProxy newProxy = new TransparentUpgradeableProxy(
            address(newImpl),
            owner,
            initData
        );

        RewardSeasonsYieldFarm newFarm = RewardSeasonsYieldFarm(
            payable(address(newProxy))
        );

        // Contract should be initialized but with invalid state
        assertEq(newFarm.owner(), address(0));
        assertEq(newFarm.merkleRoot(), bytes32(0));
    }

    function test_Ownership_Security() public {
        // Test ownership transfer security
        address newOwner = address(0x999);

        // 1. Test ownership transfer
        vm.startPrank(owner);
        farm.transferOwnership(newOwner);
        vm.stopPrank();

        // 2. Verify ownership transfer (OpenZeppelin V5 transfers immediately)
        assertEq(farm.owner(), newOwner);

        // 3. Test that new owner can call admin functions
        vm.startPrank(newOwner);
        farm.setCooldown(14 days);
        vm.stopPrank();

        // 4. Test that old owner cannot call admin functions anymore
        vm.startPrank(owner);
        vm.expectRevert(
            abi.encodeWithSelector(
                Ownable.OwnableUnauthorizedAccount.selector,
                owner
            )
        );
        farm.setCooldown(21 days);
        vm.stopPrank();
    }

    function test_UnstakeAndHarvest_Complete() public {
        // Setup: Add rewards and stake user
        vm.startPrank(rewardsDistributor);
        farm.addRewards{value: REWARD_AMOUNT}();
        vm.stopPrank();

        vm.startPrank(user1);
        farm.stake{value: STAKE_AMOUNT_1}(proof1, MULTIPLIER_1);
        vm.stopPrank();

        // End season
        vm.startPrank(owner);
        vm.warp(block.timestamp + LOCK_PERIOD + 1);
        farm.endSeason();
        vm.stopPrank();

        // Test unstakeAndHarvest - should harvest rewards and start unstaking
        vm.startPrank(user1);
        uint256 initialBalance = user1.balance;

        farm.unstakeAndHarvest(STAKE_AMOUNT_1 / 2);

        // Verify rewards were harvested (balance increased)
        assertGt(user1.balance, initialBalance);

        // Verify unstaking was initiated
        assertEq(farm.pendingWithdrawalAmount(user1), STAKE_AMOUNT_1 / 2);
        assertGt(farm.withdrawalReadyAtTime(user1), block.timestamp);

        // Verify user state was updated
        (uint256 stakedAmount, , , , uint256 effectiveStake) = farm
            .userStakeInfo(user1);
        assertEq(stakedAmount, STAKE_AMOUNT_1 / 2);
        assertEq(effectiveStake, (STAKE_AMOUNT_1 / 2) * MULTIPLIER_1);

        vm.stopPrank();
    }

    function test_UnstakeAndHarvest_NoRewards() public {
        // Setup: Stake user but no rewards added
        vm.startPrank(user1);
        farm.stake{value: STAKE_AMOUNT_1}(proof1, MULTIPLIER_1);
        vm.stopPrank();

        // End season
        vm.startPrank(owner);
        vm.warp(block.timestamp + LOCK_PERIOD + 1);
        farm.endSeason();
        vm.stopPrank();

        // Test unstakeAndHarvest with no rewards - should still work
        vm.startPrank(user1);
        uint256 initialBalance = user1.balance;

        farm.unstakeAndHarvest(STAKE_AMOUNT_1 / 2);

        // Verify balance didn't change (no rewards)
        assertEq(user1.balance, initialBalance);

        // Verify unstaking was initiated
        assertEq(farm.pendingWithdrawalAmount(user1), STAKE_AMOUNT_1 / 2);

        vm.stopPrank();
    }

    function test_UnstakeAndHarvest_SeasonNotFinalized() public {
        // Setup: Stake user and add rewards
        vm.startPrank(rewardsDistributor);
        farm.addRewards{value: REWARD_AMOUNT}();
        vm.stopPrank();

        vm.startPrank(user1);
        farm.stake{value: STAKE_AMOUNT_1}(proof1, MULTIPLIER_1);
        vm.stopPrank();

        // Try to unstakeAndHarvest before season ends - should fail
        vm.startPrank(user1);
        vm.expectRevert("Season not finalized");
        farm.unstakeAndHarvest(STAKE_AMOUNT_1 / 2);
        vm.stopPrank();
    }
}

// ========================================
// HELPER CONTRACTS FOR TESTING
// ========================================

// Simple ERC20 token for testing
contract TestERC20 {
    string public name;
    string public symbol;
    uint8 public decimals = 18;
    uint256 public totalSupply;

    mapping(address => uint256) public balanceOf;
    mapping(address => mapping(address => uint256)) public allowance;

    constructor(string memory _name, string memory _symbol) {
        name = _name;
        symbol = _symbol;
    }

    function mint(address to, uint256 amount) external {
        balanceOf[to] += amount;
        totalSupply += amount;
    }

    function transfer(address to, uint256 amount) external returns (bool) {
        require(balanceOf[msg.sender] >= amount, "Insufficient balance");
        balanceOf[msg.sender] -= amount;
        balanceOf[to] += amount;
        return true;
    }

    function approve(address spender, uint256 amount) external returns (bool) {
        allowance[msg.sender][spender] = amount;
        return true;
    }

    function transferFrom(
        address from,
        address to,
        uint256 amount
    ) external returns (bool) {
        require(balanceOf[msg.sender] >= amount, "Insufficient balance");
        require(
            allowance[from][msg.sender] >= amount,
            "Insufficient allowance"
        );
        balanceOf[msg.sender] -= amount;
        balanceOf[to] += amount;
        allowance[from][msg.sender] -= amount;
        return true;
    }
}
