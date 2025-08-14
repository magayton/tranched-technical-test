// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "forge-std/Script.sol";

// Third script to call, it withdraws funds from the contract
// It requires the flag to be set to 1 and the sender to be the owner
contract WithdrawVerbose is Script {
    address constant CONTRACT_ADDRESS = 0x931188d102a8cFe2FAC8B698D350B9BB902e2EB0;

    function run() external {

        vm.startBroadcast();

        (bool success, bytes memory returnData) = CONTRACT_ADDRESS.call(abi.encodeWithSelector(bytes4(0xc9547792)));
        vm.stopBroadcast();

        if (success) {
            console.log("Withdraw call succeeded.");
        } else {
            console.log("Withdraw call reverted.");
            console.log("Revert data:", vm.toString(returnData));
        }
    }
}
