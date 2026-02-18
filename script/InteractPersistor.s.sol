// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "../lib/openzeppelin-contracts/lib/forge-std/src/Script.sol";
import "../src/HavonaPersistor.sol";

contract InteractPersistor is Script {
    HavonaPersistor persistor;

    function setUp() public {
        // Get contract address directly from environment variable
        address contractAddress = vm.envOr("CONTRACT_ADDRESS", address(0xe7f1725E7734CE288F8367e1Bb143E90bb3F0512));

        // Initialize contract instance
        persistor = HavonaPersistor(contractAddress);
        console.log("Using HavonaPersistor at:", contractAddress);
    }

    function setTestBlob() public {
        // Get private key from environment or use default Anvil private key
        uint256 deployerPrivateKey;
        if (vm.envOr("USE_DEFAULT_ANVIL_KEY", false)) {
            // First default Anvil private key
            deployerPrivateKey = 0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80;
        } else {
            deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        }

        // Create a test key and data
        bytes32 key = keccak256(abi.encodePacked("trade:test123"));
        bytes memory data = hex"a16474657374647465737432"; // CBOR for {"test": "test2"}

        // Start broadcasting transactions
        vm.startBroadcast(deployerPrivateKey);

        console.log("Calling setBlob...");
        // Set the blob
        persistor.setBlob(key, data);
        console.log("setBlob called successfully.");

        vm.stopBroadcast();

        console.log("Test blob set with key:", vm.toString(key));
    }

    function getTestBlob() public view {
        // Create the same test key
        bytes32 key = keccak256(abi.encodePacked("trade:test123"));

        // Get the blob
        bytes memory data = persistor.getBlob(key);

        console.log("Retrieved blob data (hex):", vm.toString(data));
    }
}
