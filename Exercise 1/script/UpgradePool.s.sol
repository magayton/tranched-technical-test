// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "forge-std/Script.sol";
import "forge-std/console.sol";
import {Upgrades, Options} from "openzeppelin-foundry-upgrades/Upgrades.sol";
import "../src/Pool.sol";

/**
 * @title UpgradeWithValidations
 * @notice Upgrade script using OpenZeppelin Foundry Upgrades plugin
 * This script provides :
 *      - Automatic upgrade safety validations
 *      - Storage layout compatibility checks
 *      - Upgrade deployment
 */
contract UpgradeWithValidations is Script {
    
    address public proxyAddress;
    address public proxyOwner;
    
    function setUp() public {
        proxyAddress = vm.envAddress("PROXY_ADDRESS");
        proxyOwner = vm.envAddress("PROXY_OWNER_ADDRESS");
        
        console.log("Proxy Address:", proxyAddress);
        console.log("Proxy Owner:", proxyOwner);
    }
    
    function run() external {
        uint256 proxyOwnerPrivateKey = vm.envUint("PROXY_OWNER_PRIVATE_KEY");
        
        vm.startBroadcast(proxyOwnerPrivateKey);
        
        // Perform upgrade with validations
        upgradeWithValidations();
        
        vm.stopBroadcast();
        
        // Verify upgrade success
        verifyUpgrade();
    }
    
    /**
     * @notice Upgrade proxy with safety validations
     */
    function upgradeWithValidations() internal {
        console.log("Upgrading Pool contract with validations");
        
        // Upgrade without post-upgrade function call
        console.log("Upgrading to new Pool implementation");
        Upgrades.upgradeProxy(
            proxyAddress,
            "Pool.sol",     // New implementation contract
            ""              // No function call after upgrade
        );
        
        // Other possibility (set reference contract manually)
        // (Use this if new contract doesn't have @custom:oz-upgrades-from annotation)
        /*
        Options memory opts;
        opts.referenceContract = "PoolV1.sol"; // Previous version
        Upgrades.upgradeProxy(
            proxyAddress,
            "PoolV2.sol",
            "",
            opts
        );
        */
        
        console.log("Upgrade completed successfully!");
    }
    
    /**
     * @notice Verify upgrade was successful
     */
    function verifyUpgrade() internal view {  

        // Test proxy functionality
        Pool upgradedPool = Pool(proxyAddress);
        
        // Verify basic functionality still works
        try upgradedPool.name() returns (string memory name) {
            console.log("Proxy functional, pool name:", name);
        } catch {
            revert("Proxy not functional after upgrade");
        }
        
        try upgradedPool.owner() returns (address owner) {
            console.log("Owner preserved:", owner);
        } catch {
            console.log("Could not verify owner");
        }
        
        try upgradedPool.totalSupply() returns (uint256 supply) {
            console.log("Total supply preserved:", supply);
        } catch {
            console.log("Could not verify total supply");
        }
        
        console.log("Upgrade verification completed");
    }
}