// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "../lib/openzeppelin-contracts/lib/forge-std/src/Script.sol";
import "../src/HavonaAgentRegistry.sol";
import "../src/HavonaAgentReputation.sol";

/**
 * @title DeployAgentRegistry
 * @dev Deployment script for ERC-8004 agent identity and reputation contracts
 *
 * Deploys:
 * - HavonaAgentRegistry (ERC-721 identity)
 * - HavonaAgentReputation (Feedback/reputation)
 *
 * Usage:
 *   forge script script/DeployAgentRegistry.s.sol:DeployAgentRegistry \
 *     --rpc-url http://localhost:8545 \
 *     --broadcast \
 *     --private-key $PRIVATE_KEY
 */
contract DeployAgentRegistry is Script {
    function run() external {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");

        vm.startBroadcast(deployerPrivateKey);

        HavonaAgentRegistry registry = new HavonaAgentRegistry();
        HavonaAgentReputation reputation = new HavonaAgentReputation();

        vm.stopBroadcast();

        console.log("AGENT_REGISTRY_ADDRESS:", address(registry));
        console.log("AGENT_REPUTATION_ADDRESS:", address(reputation));
    }
}
