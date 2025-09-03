// SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

import {Script} from "forge-std/Script.sol";
import {console} from "forge-std/console.sol";
import {MigrationYieldFarm} from "../src/MigrationYieldFarm.sol";
import {TransparentUpgradeableProxy} from "@openzeppelin-v5/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";

contract DeployMigrationYieldFarm is Script {
    function run() external {
        // Hardcoded deployment parameters
        bytes32 merkleRoot = 0x1234567890abcdef1234567890abcdef1234567890abcdef1234567890abcdef; // Replace with actual merkle root

        // Periods in days - hardcoded values
        uint256 lockDays = 90; // 3 months lock period
        uint256 cooldownEpochs = 1; // 1 epoch cooldown
        uint256 rewardsDays = 21; // 21 days per epoch

        address owner_ = 0x1234567890123456789012345678901234567890; // Replace with actual owner address

        vm.startBroadcast();

        // Deploy implementation
        MigrationYieldFarm implementation = new MigrationYieldFarm();

        // Prepare initialization data
        bytes memory initData = abi.encodeWithSelector(
            MigrationYieldFarm.initialize.selector,
            merkleRoot,
            lockDays * 1 days,
            cooldownEpochs * rewardsDays * 1 days, // Convert staking epochs to days
            rewardsDays * 1 days,
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
        console.log("Deployment parameters:");
        console.log("Lock period:", lockDays, "days");
        console.log("Epoch duration:", rewardsDays, "days");
        console.log("Merkle root set");

        console.log(
            "MigrationYieldFarm implementation deployed at:",
            address(implementation)
        );
        console.log("MigrationYieldFarm proxy deployed at:", address(proxy));
        console.log("ProxyAdmin automatically deployed and owned by:", owner_);
        console.log(
            "NOTE: Call initializeStaking() on the proxy to start the program"
        );
    }
}
