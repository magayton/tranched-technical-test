// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "forge-std/Script.sol";

interface IBananaVault {
    function claimBanana_NNVGDUJE(uint256 password) external;
}

contract ClaimBananaDirect is Script {
    function run() external {
        address vault = 0x92d2730Bb4cC6D6F836B6d47c5ea4a791e391821;
        // Run the python script before to get the password
        uint256 password = 10512041859969190989958573495678937286072151474677461679212467687808821191039;

        vm.startBroadcast();
        IBananaVault(vault).claimBanana_NNVGDUJE(password);
        vm.stopBroadcast();

        console.log("Password used:", password);
    }
}
