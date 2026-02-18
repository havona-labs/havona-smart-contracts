// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "../lib/openzeppelin-contracts/lib/forge-std/src/Script.sol";
import "../src/HavonaPersistor.sol";
import "../src/P256Verifier.sol";

contract DeployPersistor is Script {
    function run() external {
        // Get private key from environment (required for non-local deployments)
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");

        // Check if we should skip P256 verification (default: true for local testing)
        bool skipP256Verification = vm.envOr("SKIP_P256_VERIFICATION", true);

        // Start broadcasting transactions
        vm.startBroadcast(deployerPrivateKey);

        // Deploy the contract
        HavonaPersistor persistor = new HavonaPersistor();

        // Deploy and configure P256Verifier
        P256Verifier p256Verifier = new P256Verifier(skipP256Verification);
        persistor.setP256Verifier(address(p256Verifier));

        vm.stopBroadcast();

        // Log the addresses with special markers for easy parsing
        console.log("PERSISTOR_ADDRESS:", address(persistor));
        console.log("P256_VERIFIER_ADDRESS:", address(p256Verifier));
        console.log("P256_SKIP_VERIFICATION:", skipP256Verification);
    }
}
