// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "forge-std/Script.sol";
import "../src/USDToken.sol";

contract DeployUSDToken is Script {
    // Initial mint amount for deployer (optional)
    uint256 constant INITIAL_MINT_AMOUNT = 1_000_000e18; // 1M USD tokens
    
    // Mint initial tokens to deployer ?
    bool constant MINT_INITIAL_TOKENS = true;
    
    function run() external {
        // Get deployer private key from environment
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address deployer = vm.addr(deployerPrivateKey);
        
        console.log("Deployer address: ", deployer);
        console.log("Deployer balance: ", deployer.balance);
        
        vm.startBroadcast(deployerPrivateKey);
        
        // Deploy USDToken contract
        USDToken usdToken = new USDToken();
        
        console.log("USDToken deployed at: ", address(usdToken));
        console.log("Token name: ", usdToken.name());
        console.log("Token symbol: ", usdToken.symbol());
        console.log("Token decimals: ", usdToken.decimals());
        
        // Optionally mint initial tokens to deployer
        if (MINT_INITIAL_TOKENS) {
            usdToken.mint(deployer, INITIAL_MINT_AMOUNT);
            console.log("Minted ", INITIAL_MINT_AMOUNT / 1e18, " tokens to deployer");
            console.log("Deployer token balance: ", usdToken.balanceOf(deployer) / 1e18);
        }
        
        vm.stopBroadcast();
        
        // Deployment summary
        console.log("USDToken Address:", address(usdToken));
        console.log("Owner:", usdToken.owner());
        console.log("Total Supply:", usdToken.totalSupply() / 1e18, "tokens");
        console.log("Deployer Balance:", usdToken.balanceOf(deployer) / 1e18, "tokens");
    }
}