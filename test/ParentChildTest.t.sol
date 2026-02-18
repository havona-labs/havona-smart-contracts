// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

// Import Foundry standard library for testing utilities
import "../lib/openzeppelin-contracts/lib/forge-std/src/Test.sol";
import "../src/ParentChild.sol";

// Import the contract we want to test
// Make sure this path is correct for your project structure! Adjust if needed.

/**
 * @title Test suite for ScalableHierarchyManagerExpanded
 * @notice Demonstrates creating entities with complex, nested attributes represented
 * using the key-flattening and separate mapping paradigm. Tests with 30 attributes.
 * @dev This version focuses on state verification via assertions. Duplicate key removed.
 * @custom:timestamp Wednesday, April 9, 2025 at 11:03 PM WITA (Ubud, Bali).
 */
contract ScalableHierarchyManagerTest is Test {
    // --- State Variables ---
    ScalableHierarchyManagerExpanded internal manager;
    uint256 internal grandparentId;
    address internal owner;
    address internal user;

    // --- Setup Function ---
    function setUp() public {
        owner = address(this);
        user = address(0xABCD);
        manager = new ScalableHierarchyManagerExpanded(owner);

        bytes32[] memory gpKeys = new bytes32[](0);
        bytes32[] memory gpValues = new bytes32[](0);
        grandparentId = manager.createGrandparent(gpKeys, gpValues);
        assertTrue(grandparentId > 0, "Setup failed: Could not create Grandparent");
    }

    // --- Helper Function to Generate Attribute Keys (Corrected) ---
    function generateAttributeKeys() internal pure returns (bytes32[] memory) {
        // CORRECTED SIZE: 30 unique keys (indices 0-29)
        bytes32[] memory keys = new bytes32[](30);

        // Basic Info (0-2)
        keys[0] = keccak256(abi.encodePacked("basicInfo.name"));
        keys[1] = keccak256(abi.encodePacked("basicInfo.dob"));
        keys[2] = keccak256(abi.encodePacked("basicInfo.status"));
        // Address (3-6)
        keys[3] = keccak256(abi.encodePacked("address.street"));
        keys[4] = keccak256(abi.encodePacked("address.city"));
        keys[5] = keccak256(abi.encodePacked("address.postalCode"));
        keys[6] = keccak256(abi.encodePacked("address.country"));
        // Employment (7-8)
        keys[7] = keccak256(abi.encodePacked("employment.company"));
        keys[8] = keccak256(abi.encodePacked("employment.title"));
        // Financials (9-10)
        keys[9] = keccak256(abi.encodePacked("financials.currency"));
        keys[10] = keccak256(abi.encodePacked("financials.annualSalary"));
        // Emergency Contacts List Length (11) - Moved for clarity
        keys[11] = keccak256(abi.encodePacked("emergencyContacts.length"));
        // Emergency Contacts - Item 0 (12-14)
        keys[12] = keccak256(abi.encodePacked("emergencyContacts.0.name"));
        keys[13] = keccak256(abi.encodePacked("emergencyContacts.0.relation"));
        keys[14] = keccak256(abi.encodePacked("emergencyContacts.0.phone"));
        // Emergency Contacts - Item 1 (15-17)
        keys[15] = keccak256(abi.encodePacked("emergencyContacts.1.name"));
        keys[16] = keccak256(abi.encodePacked("emergencyContacts.1.relation"));
        keys[17] = keccak256(abi.encodePacked("emergencyContacts.1.phone"));
        // Emergency Contacts - Item 2 (18-20)
        keys[18] = keccak256(abi.encodePacked("emergencyContacts.2.name"));
        keys[19] = keccak256(abi.encodePacked("emergencyContacts.2.relation"));
        keys[20] = keccak256(abi.encodePacked("emergencyContacts.2.phone"));
        // Emergency Contacts - Item 3 (21-23)
        keys[21] = keccak256(abi.encodePacked("emergencyContacts.3.name"));
        keys[22] = keccak256(abi.encodePacked("emergencyContacts.3.relation"));
        keys[23] = keccak256(abi.encodePacked("emergencyContacts.3.phone"));
        // Emergency Contacts - Item 4 (24-26)
        keys[24] = keccak256(abi.encodePacked("emergencyContacts.4.name"));
        keys[25] = keccak256(abi.encodePacked("emergencyContacts.4.relation"));
        keys[26] = keccak256(abi.encodePacked("emergencyContacts.4.phone"));
        // Emergency Contacts - Item 5 (27-29)
        keys[27] = keccak256(abi.encodePacked("emergencyContacts.5.name"));
        keys[28] = keccak256(abi.encodePacked("emergencyContacts.5.relation"));
        keys[29] = keccak256(abi.encodePacked("emergencyContacts.5.phone"));

        return keys;
    }

    // --- Helper Function to Generate Attribute Values (Corrected) ---
    function generateAttributeValues() internal pure returns (bytes32[] memory) {
        // CORRECTED SIZE: 30 values (indices 0-29)
        bytes32[] memory values = new bytes32[](30);

        // Basic Info Values (0-2)
        values[0] = keccak256(abi.encodePacked("Alice Parent"));
        values[1] = keccak256(abi.encodePacked("1980-05-15"));
        values[2] = keccak256(abi.encodePacked("active"));
        // Address Values (3-6)
        values[3] = keccak256(abi.encodePacked("123 Main St"));
        values[4] = keccak256(abi.encodePacked("Anytown"));
        values[5] = keccak256(abi.encodePacked("12345"));
        values[6] = bytes32(abi.encodePacked("IDN"));
        // Employment Values (7-8)
        values[7] = keccak256(abi.encodePacked("MegaCorp"));
        values[8] = keccak256(abi.encodePacked("Lead Developer"));
        // Financials Values (9-10)
        values[9] = bytes32(abi.encodePacked("IDR"));
        values[10] = bytes32(uint256(500000000));
        // Emergency Contacts List Length (11) - CORRECTED VALUE
        values[11] = bytes32(uint256(6)); // Contacts 0 through 5 exist
        // Emergency Contacts - Item 0 Values (12-14)
        values[12] = keccak256(abi.encodePacked("Bob Relative"));
        values[13] = keccak256(abi.encodePacked("Brother"));
        values[14] = keccak256(abi.encodePacked("+6281234567890"));
        // Emergency Contacts - Item 1 Values (15-17)
        values[15] = keccak256(abi.encodePacked("Charlie Friend"));
        values[16] = keccak256(abi.encodePacked("Best Friend"));
        values[17] = keccak256(abi.encodePacked("+6289876543210"));
        // Emergency Contacts - Item 2 Values (18-20)
        values[18] = keccak256(abi.encodePacked("David Colleague"));
        values[19] = keccak256(abi.encodePacked("Work Colleague"));
        values[20] = keccak256(abi.encodePacked("+6281122334455"));
        // Emergency Contacts - Item 3 Values (21-23)
        values[21] = keccak256(abi.encodePacked("Eve Neighbor"));
        values[22] = keccak256(abi.encodePacked("Next Door"));
        values[23] = keccak256(abi.encodePacked("+6285566778899"));
        // Emergency Contacts - Item 4 Values (24-26)
        values[24] = keccak256(abi.encodePacked("Frank Parent"));
        values[25] = keccak256(abi.encodePacked("Father"));
        values[26] = keccak256(abi.encodePacked("+6289988776655"));
        // Emergency Contacts - Item 5 Values (27-29)
        values[27] = keccak256(abi.encodePacked("Grace Sibling"));
        values[28] = keccak256(abi.encodePacked("Sister"));
        values[29] = keccak256(abi.encodePacked("+6283344556677"));

        return values;
    }

    // --- Test Function ---
    function testCreateParentWithNestedAttributes() public {
        // 1. Prepare Keys and Values
        bytes32[] memory keys = generateAttributeKeys();
        bytes32[] memory values = generateAttributeValues();
        assertEq(keys.length, values.length, "Test setup: Keys/Values length mismatch");
        assertEq(keys.length, 30, "Test setup: Expected 30 keys/values"); // Check correct size

        console2.log("Number of attributes being set:", keys.length);

        // 2. Call createParent
        uint256 parentId = manager.createParent(grandparentId, keys, values);

        // 3. Assertions
        assertTrue(parentId > 0, "Parent ID should be greater than 0");
        assertEq(parentId, 1, "Expected first Parent ID to be 1");

        // 3a. Check core Parent info
        ScalableHierarchyManagerExpanded.Parent memory parentInfo = manager.getParentInfo(parentId);
        assertTrue(parentInfo.exists, "Parent should exist");
        assertEq(parentInfo.grandparentId, grandparentId, "Parent's gpID mismatch");

        // 3b. Check specific attributes
        console2.log("Checking retrieved attributes...");

        // Check Basic Info -> Name
        assertEq(manager.getParentAttribute(parentId, keys[0]), values[0], "Name attribute mismatch");
        console2.log("  Name OK");

        // Check Address -> City
        assertEq(manager.getParentAttribute(parentId, keys[4]), values[4], "City attribute mismatch");
        console2.log("  City OK");

        // Check Financials -> Salary
        assertEq(manager.getParentAttribute(parentId, keys[10]), values[10], "Salary attribute mismatch");
        console2.log("  Salary OK");

        // Check the list length (CORRECTED check)
        bytes32 keyContactsLength = keys[11]; // Key is now at index 11
        bytes32 expectedContactsLengthValue = values[11]; // Expected value (6) is now at index 11
        assertEq(
            manager.getParentAttribute(parentId, keyContactsLength),
            expectedContactsLengthValue,
            "Contacts length mismatch"
        );
        console2.log("  Contacts length OK");

        // Check one of the added contacts (e.g., contact 5 phone - now at index 29)
        bytes32 keyContact5Phone = keys[29];
        bytes32 expectedContact5PhoneValue = values[29];
        assertEq(
            manager.getParentAttribute(parentId, keyContact5Phone),
            expectedContact5PhoneValue,
            "Contact 5 Phone mismatch"
        );
        console2.log("  Contact 5 Phone OK");
    }
}
