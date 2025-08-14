// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "forge-std/Script.sol";
import "forge-std/console.sol";
import {Upgrades} from "openzeppelin-foundry-upgrades/Upgrades.sol";
import "../src/Pool.sol";
import "../src/USDToken.sol";

/**
 * @title DeployWithUpgrades
 * @notice Deployment script using OpenZeppelin Foundry Upgrades plugin
 * Uses the OpenZeppelin tooling for:
 *      - Automated upgrade safety validations
 *      - Simplified proxy deployment
 *      - Storage layout compatibility checks
 */
contract DeployWithUpgrades is Script {
    
    string constant POOL_NAME = "Pool USD Token";
    string constant POOL_SYMBOL = "pUSD";
    
    string constant USD_NAME = "USD Token";
    string constant USD_SYMBOL = "USD";
    uint256 constant USD_INITIAL_SUPPLY = 1_000_000 * 1e18;
    
    USDToken public usdToken;
    address public poolProxy;
    Pool public pool;
    
    address public deployer;
    address public poolAdmin;
    address public proxyOwner;
    
    function setUp() public {
        deployer = vm.envAddress("DEPLOYER_ADDRESS");
        poolAdmin = vm.envOr("POOL_ADMIN_ADDRESS", deployer);
        proxyOwner = vm.envOr("PROXY_OWNER_ADDRESS", deployer);
        usdToken = USDToken(vm.envAddress("USD_TOKEN_ADDRESS"));
        
        console.log("DEPLOYMENT CONFIGURATION");
        console.log("Deployer:", deployer);
        console.log("Pool Admin:", poolAdmin);
        console.log("Proxy Owner:", proxyOwner);
    }
    
    function run() external {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        
        vm.startBroadcast(deployerPrivateKey);
        
        // Deploy Pool with transparent proxy using OpenZeppelin tooling
        deployPoolWithProxy();
        
        vm.stopBroadcast();
        
        // Log results
        logDeploymentResults();
    }


    // Deploy Pool using OpenZeppelin Upgrades plugin
    function deployPoolWithProxy() internal {
        console.log("Deploying Pool with TransparentUpgradeableProxy");
        
        // initialization data
        bytes memory initializerData = abi.encodeCall(
            Pool.initialize,
            (address(usdToken), poolAdmin, POOL_NAME, POOL_SYMBOL)
        );
        
        // Deploy transparent proxy
        // This function does the following:
        // 1. Validates Pool.sol for upgrade safety
        // 2. Deploys Pool implementation
        // 3. Deploys ProxyAdmin (owned by proxyOwner)
        // 4. Deploys TransparentUpgradeableProxy
        // 5. Initializes Pool through proxy
        poolProxy = Upgrades.deployTransparentProxy(
            "Pool.sol",           
            proxyOwner,          // Initial owner of ProxyAdmin
            initializerData      // Initialization call data
        );
        
        // Create Pool interface through proxy
        pool = Pool(poolProxy);
        
        console.log("Pool Proxy Address:", poolProxy);
        console.log("Pool accessible through proxy at:", address(pool));
    }
    

    // Log deployment results
    function logDeploymentResults() internal view {
        console.log("DEPLOYMENT RESULTS");
        console.log("USD Token:", address(usdToken));
        console.log("Pool (via proxy):", poolProxy);
        
        console.log("CONTRACT INFO");
        console.log("Pool Name:", pool.name());
        console.log("Pool Symbol:", pool.symbol());
        console.log("Pool Owner:", pool.owner());
        console.log("USD Token in Pool:", address(pool.usdToken()));
    }
}