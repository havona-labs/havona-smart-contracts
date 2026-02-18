// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "../lib/openzeppelin-contracts/lib/forge-std/src/Script.sol";
import {HavonaMemberManager} from "../src/HavonaMemberManager.sol";

contract Interactions is Script {
    HavonaMemberManager manager;
    address constant CONTRACT_ADDRESS = 0x5FbDB2315678afecb367f032d93F642f64180aa3;

    function setUp() public {
        manager = HavonaMemberManager(CONTRACT_ADDRESS);
    }
    //###############################################
    // Add new member
    // forge script script/Interactions.s.sol:Interactions --sig "addNewMember()" --rpc-url http://localhost:8545 --private-key 0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80 --broadcast

    function addNewMember() public {
        vm.broadcast();
        manager.addMember(
            address(0x1234),
            "Test Company",
            HavonaMemberManager.CompanyInformation({name: "Company Name", details: "Company Info"}),
            "Contact",
            "PubKey"
        );
    }

    //###############################################
    // Read member details (replace ADDRESS with actual address)
    // forge script script/Interactions.s.sol:Interactions --sig "readMember(address)" 0x1234 --rpc-url http://localhost:8545

    function readMember(address memberAddress) public view {
        (string memory name, bool active, string memory status) = manager.getMember(memberAddress);
        console.log("Name:", name);
        console.log("Active:", active);
        console.log("Status:", status);
    }

    //###############################################
    // Finalize a member
    // forge script script/Interactions.s.sol:Interactions --sig "finalizeMember(address)" 0x1234 --rpc-url http://localhost:8545 --private-key 0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80 --broadcast

    function finalizeMember(address memberAddress) public {
        vm.broadcast();
        manager.finalizeMember(memberAddress);
    }
}
