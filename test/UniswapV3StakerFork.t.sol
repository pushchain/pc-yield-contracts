// SPDX-License-Identifier: MIT
pragma solidity 0.7.6;
pragma abicoder v2;

import {Test} from "forge-std/Test.sol";

import {UniswapV3Staker} from "../src/LPYield/UniswapV3Staker.sol";
import {IUniswapV3Staker} from "../src/LPYield/interfaces/IUniswapV3Staker.sol";
import {INonfungiblePositionManager} from "@uniswap/v3-periphery/contracts/interfaces/INonfungiblePositionManager.sol";
import {IERC721} from "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import {IERC20Minimal} from "@uniswap/v3-core/contracts/interfaces/IERC20Minimal.sol";
import {IUniswapV3Pool} from "@uniswap/v3-core/contracts/interfaces/IUniswapV3Pool.sol";
import {IUniswapV3Factory} from "@uniswap/v3-core/contracts/interfaces/IUniswapV3Factory.sol";

/// @title UniswapV3StakerForkTest
/// @notice Fork-based tests for Uniswap V3 Staker using Push Chain testnet
contract UniswapV3StakerForkTest is Test {
    // Push Chain testnet addresses
    address constant FACTORY = 0xF02DA51d1Ef1c593a95f5C97d7BdFc49fbaBbaA5;
    address constant WPUSH = 0x2c7EbF633ffC84ea67eB6C8B232DC5f42970B818;
    address constant PUSDC = 0xBeEcDAf9aE39d6c71c29F0344346F6B4C500BB4F;
    address constant POSITION_MANAGER = 0xf90F08fD301190Cd34CC9eFc5A76351e95051670;
    address constant WPUSH_PUSDC_POOL = 0xdd48D507908F9ebffbe28D6FbE28a167aA449841;

    // Real user address - the ONLY address we use for testing
    address constant REAL_USER = 0xEbf0Cfc34E07ED03c05615394E2292b387B63F12;

    // Contracts
    UniswapV3Staker public staker;
    IERC20Minimal public wpushToken;
    IERC20Minimal public pusdcToken;
    INonfungiblePositionManager public positionManager;
    IUniswapV3Pool public pool;
    IUniswapV3Factory public factory;

    // Test constants
    uint256 public constant MAX_INCENTIVE_DURATION = 30 days;
    uint256 public constant MAX_INCENTIVE_START_LEAD_TIME = 1 days;
    uint256 public constant REWARD_AMOUNT = 1000e18;

    function setUp() public {
        // Fork the Push Chain testnet
        vm.createSelectFork("https://evm.rpc-testnet-donut-node1.push.org/");

        // No fake addresses - using only real user

        // Setup contract instances
        factory = IUniswapV3Factory(FACTORY);
        wpushToken = IERC20Minimal(WPUSH);
        pusdcToken = IERC20Minimal(PUSDC);
        positionManager = INonfungiblePositionManager(POSITION_MANAGER);
        pool = IUniswapV3Pool(WPUSH_PUSDC_POOL);

        // Deploy Uniswap V3 Staker
        staker = new UniswapV3Staker(factory, positionManager, MAX_INCENTIVE_START_LEAD_TIME, MAX_INCENTIVE_DURATION);

        // NO FAKE FUNDING - USE ONLY REAL TOKENS
    }

    // --------------------------------------------------
    // Basic Setup Tests
    // --------------------------------------------------

    function test_Setup() public {
        assertEq(address(staker.factory()), FACTORY);
        assertEq(address(staker.nonfungiblePositionManager()), POSITION_MANAGER);
        assertEq(staker.maxIncentiveStartLeadTime(), MAX_INCENTIVE_START_LEAD_TIME);
        assertEq(staker.maxIncentiveDuration(), MAX_INCENTIVE_DURATION);
    }

    function test_RealSetupVerification() public {
        // Verify real testnet deployment
        assertEq(address(staker.factory()), FACTORY);
        assertEq(address(staker.nonfungiblePositionManager()), POSITION_MANAGER);

        // Verify real tokens and pool exist
        uint256 wpushBalance = wpushToken.balanceOf(REAL_USER);
        uint256 pusdcBalance = pusdcToken.balanceOf(REAL_USER);
        assertGt(wpushBalance, 0, "Real user should have WPUSH tokens");
        assertGt(pusdcBalance, 0, "Real user should have pUSDC tokens");

        address poolAddress = factory.getPool(WPUSH, PUSDC, 500);
        assertEq(poolAddress, WPUSH_PUSDC_POOL);
    }

    /// @notice COMPLETE LIFECYCLE TEST - NO MOCKS OR FAKE DATA
    /// Tests: Deployment → Incentive Creation → LP Staking → Reward Distribution → Claiming → Unstaking
    /// Answers: How rewards are distributed between early vs late stakers
    function test_CompleteRealLifecycleStaking() public {
        // PHASE 1: VERIFY REAL DEPLOYMENT
        _verifyRealDeployment();

        // PHASE 2: CREATE REAL INCENTIVE
        IUniswapV3Staker.IncentiveKey memory key = _createRealIncentive();
        bytes32 incentiveId = keccak256(abi.encode(key));

        // PHASE 3: FIND REAL LP POSITIONS
        (uint256 earlyTokenId, uint256 lateTokenId) = _findRealLPPositions();

        // PHASE 4: TEST EARLY VS LATE STAKING REWARDS
        _testEarlyVsLateStakingRewards(key, incentiveId, earlyTokenId, lateTokenId);

        // PHASE 5: COMPLETE LIFECYCLE VERIFICATION
        _verifyCompleteLifecycle(key, incentiveId, earlyTokenId, lateTokenId);
    }

    function _verifyRealDeployment() internal {
        // Verify staker deployed with real testnet contracts
        assertEq(address(staker.factory()), FACTORY);
        assertEq(address(staker.nonfungiblePositionManager()), POSITION_MANAGER);

        // Verify real user has tokens (use whatever they have)
        uint256 wpushBalance = wpushToken.balanceOf(REAL_USER);
        require(wpushBalance > 10e18, "Real user needs at least 10 WPUSH");

        // Verify real pool exists
        address poolAddress = factory.getPool(WPUSH, PUSDC, 500);
        assertEq(poolAddress, WPUSH_PUSDC_POOL);
    }

    function _createRealIncentive() internal returns (IUniswapV3Staker.IncentiveKey memory key) {
        vm.startPrank(REAL_USER);

        key = IUniswapV3Staker.IncentiveKey({
            rewardToken: wpushToken,
            pool: pool,
            startTime: block.timestamp,
            endTime: block.timestamp + 30 days,
            refundee: REAL_USER
        });

        // Use real WPUSH tokens for rewards (use 10% of user balance)
        uint256 userBalance = wpushToken.balanceOf(REAL_USER);
        uint256 incentiveAmount = userBalance / 10;

        // Approve staker to pull tokens (this is how createIncentive works)
        wpushToken.approve(address(staker), incentiveAmount);
        staker.createIncentive(key, incentiveAmount);

        // Verify incentive created
        bytes32 incentiveId = keccak256(abi.encode(key));
        (uint256 rewards,, uint96 stakes) = staker.incentives(incentiveId);
        assertEq(rewards, incentiveAmount);
        assertEq(uint256(stakes), 0);

        vm.stopPrank();
    }

    function _findRealLPPositions() internal returns (uint256 earlyTokenId, uint256 lateTokenId) {
        uint256 balance = positionManager.balanceOf(REAL_USER);
        require(balance > 0, "Real user needs LP positions");

        uint256 foundCount = 0;
        for (uint256 i = 0; i < balance && foundCount < 2; i++) {
            uint256 tokenId = positionManager.tokenOfOwnerByIndex(REAL_USER, i);

            // Get position details with simplified destructuring
            (,, address token0, address token1,,,, uint128 liquidity,,,,) = positionManager.positions(tokenId);

            bool isWpushPool = (token0 == WPUSH && token1 == PUSDC) || (token0 == PUSDC && token1 == WPUSH);

            if (isWpushPool && liquidity > 0) {
                if (foundCount == 0) earlyTokenId = tokenId;
                else lateTokenId = tokenId;
                foundCount++;
            }
        }

        require(foundCount >= 2, "Need at least 2 WPUSH/pUSDC positions");
    }

    function _testEarlyVsLateStakingRewards(
        IUniswapV3Staker.IncentiveKey memory key,
        bytes32 incentiveId,
        uint256 earlyTokenId,
        uint256 lateTokenId
    ) internal {
        vm.startPrank(REAL_USER);

        // EARLY STAKER: Stake at beginning
        positionManager.approve(address(staker), earlyTokenId);
        positionManager.safeTransferFrom(REAL_USER, address(staker), earlyTokenId, abi.encode(key));

        // Verify early staking
        (,, uint96 stakes) = staker.incentives(incentiveId);
        assertEq(uint256(stakes), 1);

        // TIME PASSAGE: 15 days
        vm.warp(block.timestamp + 15 days);

        // Check early staker pending rewards (use getRewardInfo, not rewards mapping)
        (uint256 earlyPendingRewards,) = staker.getRewardInfo(key, earlyTokenId);
        assertGt(earlyPendingRewards, 0, "Early staker should have pending rewards");

        // LATE STAKER: Stake at day 15
        positionManager.approve(address(staker), lateTokenId);
        positionManager.safeTransferFrom(REAL_USER, address(staker), lateTokenId, abi.encode(key));

        // Verify both positions staked
        (,, stakes) = staker.incentives(incentiveId);
        assertEq(uint256(stakes), 2);

        vm.stopPrank();
    }

    function _verifyCompleteLifecycle(
        IUniswapV3Staker.IncentiveKey memory key,
        bytes32 incentiveId,
        uint256 earlyTokenId,
        uint256 lateTokenId
    ) internal {
        vm.startPrank(REAL_USER);

        // TIME: Go to day 25 (before incentive ends)
        vm.warp(block.timestamp + 10 days);

        // Check pending rewards for both positions
        (uint256 earlyPendingRewards,) = staker.getRewardInfo(key, earlyTokenId);
        (uint256 latePendingRewards,) = staker.getRewardInfo(key, lateTokenId);

        assertGt(earlyPendingRewards, 0, "Early staker should have pending rewards");
        assertGt(latePendingRewards, 0, "Late staker should have pending rewards");

        // Early staker should have more rewards (staked for 25 days vs 10 days)
        assertGt(earlyPendingRewards, latePendingRewards, "Early staker should have more rewards");

        // UNSTAKE POSITIONS (this moves rewards to rewards mapping)
        staker.unstakeToken(key, earlyTokenId);
        staker.unstakeToken(key, lateTokenId);

        // Now check actual claimed rewards in the rewards mapping
        uint256 totalEarnedRewards = staker.rewards(wpushToken, REAL_USER);
        assertGt(totalEarnedRewards, 0, "Should have earned rewards from unstaking");

        // CLAIM REWARDS
        uint256 balanceBefore = wpushToken.balanceOf(REAL_USER);
        staker.claimReward(wpushToken, REAL_USER, type(uint256).max);
        uint256 balanceAfter = wpushToken.balanceOf(REAL_USER);
        uint256 totalClaimed = balanceAfter - balanceBefore;

        assertEq(totalClaimed, totalEarnedRewards, "Claimed amount should match earned rewards");
        assertEq(staker.rewards(wpushToken, REAL_USER), 0, "Rewards should be zero after claiming");

        // WITHDRAW POSITIONS (this actually returns NFTs to user)
        staker.withdrawToken(earlyTokenId, REAL_USER, "");
        staker.withdrawToken(lateTokenId, REAL_USER, "");

        // Verify positions returned
        assertEq(positionManager.ownerOf(earlyTokenId), REAL_USER);
        assertEq(positionManager.ownerOf(lateTokenId), REAL_USER);

        // Verify no stakes remain
        (,, uint96 finalStakes) = staker.incentives(incentiveId);
        assertEq(uint256(finalStakes), 0);

        // END INCENTIVE (move to after end time first)
        vm.warp(key.endTime + 1);
        staker.endIncentive(key);

        vm.stopPrank();

        // FINAL VERIFICATION: Proved time-weighted reward distribution
        // Early staker (25 days) > Late staker (10 days) ✅
        // Real rewards claimed successfully ✅
    }

    /// @notice CRITICAL TEST: Early reward claiming vs Late stakers
    /// Tests the scenario where early stakers claim rewards before epoch ends
    /// and verifies late stakers still get their fair share
    function test_EarlyClaimingVsLateStakers() public {
        IUniswapV3Staker.IncentiveKey memory key = _createRealIncentive();
        bytes32 incentiveId = keccak256(abi.encode(key));
        (uint256 earlyTokenId, uint256 lateTokenId) = _findRealLPPositions();

        // Early phase: stake and claim mid-epoch
        uint256 earlyClaimed = _earlyStakeAccrueAndClaim(key, earlyTokenId);
        assertGt(earlyClaimed, 0, "Early staker should claim some rewards");

        // Late phase: stake after early claimed, then accrue and claim
        (uint256 remainingRewards,,) = staker.incentives(incentiveId);
        assertGt(remainingRewards, 0, "Rewards must remain for late staker");

        uint256 lateClaimed = _lateStakeAccrueAndClaim(key, incentiveId, lateTokenId);
        assertGt(lateClaimed, 0, "Late staker should also claim rewards");

        // Withdraw NFTs back to user
        vm.startPrank(REAL_USER);
        staker.withdrawToken(earlyTokenId, REAL_USER, "");
        staker.withdrawToken(lateTokenId, REAL_USER, "");
        vm.stopPrank();

        // End incentive
        vm.warp(key.endTime + 1);
        staker.endIncentive(key);

        // Both stakers successfully earned despite early claiming
        assertGt(earlyClaimed + lateClaimed, 0, "Total claimed should be > 0");
    }

    function _earlyStakeAccrueAndClaim(IUniswapV3Staker.IncentiveKey memory key, uint256 tokenId)
        internal
        returns (uint256 claimed)
    {
        vm.startPrank(REAL_USER);
        positionManager.approve(address(staker), tokenId);
        positionManager.safeTransferFrom(REAL_USER, address(staker), tokenId, abi.encode(key));
        vm.warp(block.timestamp + 10 days);
        (uint256 pending,) = staker.getRewardInfo(key, tokenId);
        assertGt(pending, 0, "Pending must be > 0 before claiming");
        staker.unstakeToken(key, tokenId);
        uint256 owed = staker.rewards(wpushToken, REAL_USER);
        assertGt(owed, 0, "Owed must be > 0 after unstake");
        uint256 beforeBal = wpushToken.balanceOf(REAL_USER);
        staker.claimReward(wpushToken, REAL_USER, type(uint256).max);
        uint256 afterBal = wpushToken.balanceOf(REAL_USER);
        claimed = afterBal - beforeBal;
        vm.stopPrank();
    }

    function _lateStakeAccrueAndClaim(IUniswapV3Staker.IncentiveKey memory key, bytes32 incentiveId, uint256 tokenId)
        internal
        returns (uint256 claimed)
    {
        vm.startPrank(REAL_USER);
        positionManager.approve(address(staker), tokenId);
        positionManager.safeTransferFrom(REAL_USER, address(staker), tokenId, abi.encode(key));
        (,, uint96 stakes) = staker.incentives(incentiveId);
        assertEq(uint256(stakes), 1, "Only late staker should be active");
        vm.warp(block.timestamp + 10 days);
        (uint256 pending,) = staker.getRewardInfo(key, tokenId);
        assertGt(pending, 0, "Late must have pending rewards");
        staker.unstakeToken(key, tokenId);
        uint256 owed = staker.rewards(wpushToken, REAL_USER);
        assertGt(owed, 0, "Owed must be > 0 after late unstake");
        uint256 beforeBal = wpushToken.balanceOf(REAL_USER);
        staker.claimReward(wpushToken, REAL_USER, type(uint256).max);
        uint256 afterBal = wpushToken.balanceOf(REAL_USER);
        claimed = afterBal - beforeBal;
        vm.stopPrank();
    }
}
