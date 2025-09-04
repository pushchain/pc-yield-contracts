// SPDX-License-Identifier: MIT
pragma solidity =0.7.6;
pragma abicoder v2;

import {Script} from "forge-std/Script.sol";
import {console} from "forge-std/console.sol";
import {UniswapV3Staker} from "../src/LPYield/UniswapV3Staker.sol";
import {IUniswapV3Factory} from "@uniswap/v3-core/contracts/interfaces/IUniswapV3Factory.sol";
import {INonfungiblePositionManager} from "@uniswap/v3-periphery/contracts/interfaces/INonfungiblePositionManager.sol";

contract DeployLPYield is Script {
    function run() external {
        // Production deployment parameters for Push Chain
        address factory = 0xF02DA51d1Ef1c593a95f5C97d7BdFc49fbaBbaA5; // Push Chain Uniswap V3 Factory
        address positionManager = 0xf90F08fD301190Cd34CC9eFc5A76351e95051670; // Push Chain Position Manager

        // Incentive parameters
        uint256 maxIncentiveStartLeadTime = 30 days; // Max 30 days in advance
        uint256 maxIncentiveDuration = 90 days; // Max 3 months duration

        vm.startBroadcast();

        // Deploy Uniswap V3 Staker
        UniswapV3Staker staker = new UniswapV3Staker(
            IUniswapV3Factory(factory),
            INonfungiblePositionManager(positionManager),
            maxIncentiveStartLeadTime,
            maxIncentiveDuration
        );

        vm.stopBroadcast();

        // Log deployment parameters for verification
        console.log("LPYield UniswapV3Staker deployed at:", address(staker));
        console.log("Factory address:", factory);
        console.log("Position Manager address:", positionManager);
        console.log(
            "Max incentive start lead time:",
            maxIncentiveStartLeadTime / 1 days,
            "days"
        );
        console.log(
            "Max incentive duration:",
            maxIncentiveDuration / 1 days,
            "days"
        );

        console.log("\nDeployment verification:");
        console.log("Staker factory:", address(staker.factory()));
        console.log(
            "Staker position manager:",
            address(staker.nonfungiblePositionManager())
        );
        console.log(
            "Max start lead time:",
            staker.maxIncentiveStartLeadTime() / 1 days,
            "days"
        );
        console.log(
            "Max duration:",
            staker.maxIncentiveDuration() / 1 days,
            "days"
        );

        console.log("\nNext steps:");
        console.log("1. Verify contract addresses on Push Chain explorer");
        console.log("2. Create incentives using createIncentive()");
        console.log("3. Users can stake LP positions for rewards");
    }
}
