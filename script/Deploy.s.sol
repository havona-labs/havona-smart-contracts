// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "../lib/openzeppelin-contracts/lib/forge-std/src/Script.sol";
import "../src/HavonaPersistor.sol";

contract Deploy is Script {
    function run() external {
        // Get private key from environment
        // uint256 deployerPrivateKey = vm.envUint("ANVIL_PRIVATE_KEY");

        // Start broadcasting transactions
        vm.startBroadcast();

        // Deploy the contract
        HavonaPersistor persistor = new HavonaPersistor();

        vm.stopBroadcast();

        // Log the address
        console.log("HavonaPersistor deployed to:", address(persistor));
    }
}
