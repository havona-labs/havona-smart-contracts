// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "../lib/openzeppelin-contracts/lib/forge-std/src/Script.sol";
import "../src/ETRRegistry.sol";

/**
 * @title DeployETRRegistry
 * @dev Deployment script for ETRRegistry contract
 *
 * ETRRegistry handles ETR (Electronic Transferable Record) lifecycle events:
 * - Pledge/release events
 * - Control transfers
 * - Liquidations
 * - Redemptions
 *
 * Usage:
 *   forge script script/DeployETRRegistry.s.sol:DeployETRRegistry \
 *     --rpc-url http://localhost:8545 \
 *     --broadcast \
 *     --unlocked \
 *     --sender 0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266
 */
contract DeployETRRegistry is Script {
    function run() external {
        // Get private key from environment (required for non-local deployments)
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");

        // Start broadcasting transactions
        vm.startBroadcast(deployerPrivateKey);

        // Deploy the contract
        ETRRegistry registry = new ETRRegistry();

        vm.stopBroadcast();

        // Log the address with a special marker for easy parsing
        console.log("ETR_REGISTRY_ADDRESS:", address(registry));
    }
}
