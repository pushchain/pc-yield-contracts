// SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

import {Script, console} from "forge-std/Script.sol";
import {RewardSeasonsYieldFarm} from "../src/RewardSeasonsYieldFarm.sol";
import {TransparentUpgradeableProxy} from "@openzeppelin-v5/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";

contract DeployRewardSeasonsYieldFarm is Script {
    function run() external {
        // PRODUCTION DEPLOYMENT - UPDATE THESE VALUES BEFORE DEPLOYING

        // TODO: Replace with actual production values
        bytes32 merkleRoot = 0x0000000000000000000000000000000000000000000000000000000000000000; // Set actual merkle root
        uint256 lockPeriod = 90 days; // 3 months lock period
        uint256 cooldownPeriod = 7 days; // 7 days cooldown period
        address owner_ = address(0); // Set actual owner address

        // Validate parameters
        require(
            merkleRoot !=
                0x0000000000000000000000000000000000000000000000000000000000000000,
            "Invalid merkle root"
        );
        require(owner_ != address(0), "Invalid owner address");
        require(lockPeriod >= 30 days, "Lock period too short");
        require(cooldownPeriod >= 1 days, "Cooldown period too short");

        vm.startBroadcast();

        // Deploy implementation
        RewardSeasonsYieldFarm implementation = new RewardSeasonsYieldFarm();

        // Prepare initialization data
        bytes memory initData = abi.encodeWithSelector(
            RewardSeasonsYieldFarm.initialize.selector,
            merkleRoot,
            lockPeriod,
            cooldownPeriod,
            owner_
        );

        // Deploy transparent proxy (ProxyAdmin is automatically deployed)
        TransparentUpgradeableProxy proxy = new TransparentUpgradeableProxy(
            address(implementation),
            owner_, // admin address
            initData
        );

        vm.stopBroadcast();

        // Log deployment parameters for verification
        console.log("=== REWARD SEASONS YIELD FARM DEPLOYMENT ===");
        console.log("Implementation deployed at:", address(implementation));
        console.log("Proxy deployed at:", address(proxy));
        console.log("Owner:", owner_);
        console.log("Lock period:", lockPeriod / 1 days, "days");
        console.log("Cooldown period:", cooldownPeriod / 1 days, "days");
    }
}
