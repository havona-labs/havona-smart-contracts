// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "../lib/openzeppelin-contracts/lib/forge-std/src/Script.sol";
import "../src/HavonaMemberManager.sol";

contract DeployMemberManager is Script {
    function run() external {
        // Get private key from environment (required for non-local deployments)
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");

        // Start broadcasting transactions
        vm.startBroadcast(deployerPrivateKey);

        // Deploy the HavonaMemberManager contract
        HavonaMemberManager memberManager = new HavonaMemberManager();

        vm.stopBroadcast();

        // Log the deployed address
        console.log("HavonaMemberManager deployed to:", address(memberManager));
        console.log("Owner:", memberManager.owner());
    }
}
