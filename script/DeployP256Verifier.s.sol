// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Script.sol";
import "../src/P256Verifier.sol";
import "../src/HavonaPersistor.sol";

/**
 * @title DeployP256Verifier
 * @notice Deploy P256Verifier and configure HavonaPersistor
 *
 * Usage:
 *   # Local Anvil (skip verification for testing)
 *   forge script script/DeployP256Verifier.s.sol:DeployP256Verifier \
 *     --rpc-url http://localhost:8545 \
 *     --broadcast \
 *     -vvv
 *
 *   # Production (real verification)
 *   SKIP_VERIFICATION=false forge script script/DeployP256Verifier.s.sol:DeployP256Verifier \
 *     --rpc-url $TEN_RPC_URL \
 *     --broadcast \
 *     -vvv
 */
contract DeployP256Verifier is Script {
    function run() external {
        // Check if we should skip verification (default: true for local testing)
        bool skipVerification = vm.envOr("SKIP_VERIFICATION", true);

        // Get existing HavonaPersistor address if available
        address persistorAddress = vm.envOr("HAVONA_PERSISTOR", address(0));

        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");

        vm.startBroadcast(deployerPrivateKey);

        // Deploy P256Verifier
        P256Verifier verifier = new P256Verifier(skipVerification);
        console.log("P256Verifier deployed at:", address(verifier));
        console.log("  skipVerification:", skipVerification);

        // If HavonaPersistor address is provided, configure it
        if (persistorAddress != address(0)) {
            HavonaPersistor persistor = HavonaPersistor(persistorAddress);
            persistor.setP256Verifier(address(verifier));
            console.log("HavonaPersistor configured with P256Verifier");
        } else {
            console.log("HAVONA_PERSISTOR not set - configure manually:");
            console.log("  persistor.setP256Verifier(", address(verifier), ")");
        }

        vm.stopBroadcast();
    }
}
