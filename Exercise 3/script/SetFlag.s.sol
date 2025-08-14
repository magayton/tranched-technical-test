// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "forge-std/Script.sol";

// First script to call, it sets a flag in the contract that must be to 1 to change ownership
contract SetFlagBySig is Script {
    address constant CONTRACT_ADDRESS = 0x931188d102a8cFe2FAC8B698D350B9BB902e2EB0;

    function run() external {
        vm.startBroadcast();

        // Encode the function selector + uint256(1) as calldata
        bytes memory payload = abi.encodeWithSelector(
            bytes4(0xf7680ca0),
            uint256(1)
        );

        (bool success,) = CONTRACT_ADDRESS.call(payload);
        require(success, "Call failed");

        vm.stopBroadcast();
    }
}
