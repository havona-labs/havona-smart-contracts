// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "../lib/openzeppelin-contracts/lib/forge-std/src/Test.sol";
import "../src/HavonaPersistor.sol";

contract HavonaPersistorTest is Test {
    HavonaPersistor internal persistor;

    address internal owner;
    address internal user1;
    address internal user2;
    address internal unauthorized;

    uint256 internal user1PrivateKey = 0x1234;
    uint256 internal user2PrivateKey = 0x5678;

    bytes32 internal constant TEST_KEY = keccak256("test:document:001");
    bytes internal constant TEST_DATA = hex"a16474657374647465737432"; // CBOR: {"test": "test2"}

    function setUp() public {
        owner = address(this); // Test contract is owner
        user1 = vm.addr(user1PrivateKey);
        user2 = vm.addr(user2PrivateKey);
        unauthorized = address(0x999);

        persistor = new HavonaPersistor();
    }

    // ============ Ownership Tests ============

    function testOwnerCanWrite() public {
        persistor.setBlob(TEST_KEY, TEST_DATA);
        assertTrue(persistor.hasBlob(TEST_KEY));
    }

    function testNonOwnerCannotWrite() public {
        vm.prank(unauthorized);
        vm.expectRevert();
        persistor.setBlob(TEST_KEY, TEST_DATA);
    }

    // ============ Access Control Tests ============

    function testOwnerAlwaysHasAccess() public {
        persistor.setBlob(TEST_KEY, TEST_DATA);

        // Owner can read
        bytes memory retrieved = persistor.getBlob(TEST_KEY);
        assertEq(keccak256(retrieved), keccak256(TEST_DATA));
    }

    function testUnauthorizedCannotRead() public {
        persistor.setBlob(TEST_KEY, TEST_DATA);

        vm.prank(unauthorized);
        vm.expectRevert("Access denied");
        persistor.getBlob(TEST_KEY);
    }

    function testGrantAndRevokeAccess() public {
        persistor.setBlob(TEST_KEY, TEST_DATA);

        // Grant access to user1
        persistor.grantAccess(TEST_KEY, user1);
        assertTrue(persistor.hasAccess(user1, TEST_KEY));

        // User1 can now read
        vm.prank(user1);
        bytes memory retrieved = persistor.getBlob(TEST_KEY);
        assertEq(keccak256(retrieved), keccak256(TEST_DATA));

        // Revoke access
        persistor.revokeAccess(TEST_KEY, user1);
        assertFalse(persistor.hasAccess(user1, TEST_KEY));

        // User1 can no longer read
        vm.prank(user1);
        vm.expectRevert("Access denied");
        persistor.getBlob(TEST_KEY);
    }

    function testBatchAccessGrant() public {
        bytes32 key1 = keccak256("doc1");
        bytes32 key2 = keccak256("doc2");

        persistor.setBlob(key1, TEST_DATA);
        persistor.setBlob(key2, TEST_DATA);

        bytes32[] memory keys = new bytes32[](2);
        address[] memory accounts = new address[](2);

        keys[0] = key1;
        keys[1] = key2;
        accounts[0] = user1;
        accounts[1] = user2;

        persistor.grantAccessBatch(keys, accounts);

        assertTrue(persistor.hasAccess(user1, key1));
        assertTrue(persistor.hasAccess(user2, key2));
    }

    // ============ Storage Tests ============

    function testBasicStorageAndRetrieval() public {
        persistor.setBlob(TEST_KEY, TEST_DATA);

        assertTrue(persistor.hasBlob(TEST_KEY));
        assertEq(persistor.getBlobCount(), 1);

        bytes memory retrieved = persistor.getBlob(TEST_KEY);
        assertEq(keccak256(retrieved), keccak256(TEST_DATA));
    }

    function testVersioning() public {
        bytes memory data1 = hex"01";
        bytes memory data2 = hex"02";
        bytes memory data3 = hex"03";

        // Create versions
        persistor.setBlob(TEST_KEY, data1);
        persistor.setBlob(TEST_KEY, data2);
        persistor.setBlob(TEST_KEY, data3);

        assertEq(persistor.getBlobVersionCount(TEST_KEY), 2);

        // Verify versions
        bytes memory v1 = persistor.getBlobVersion(TEST_KEY, 1);
        bytes memory v2 = persistor.getBlobVersion(TEST_KEY, 2);
        bytes memory current = persistor.getBlob(TEST_KEY);

        assertEq(keccak256(v1), keccak256(data1));
        assertEq(keccak256(v2), keccak256(data2));
        assertEq(keccak256(current), keccak256(data3));
    }

    function testMaxVersionsLimit() public {
        // Create first blob
        persistor.setBlob(TEST_KEY, hex"00");

        // Hit max versions
        for (uint256 i = 1; i <= 100; i++) {
            persistor.setBlob(TEST_KEY, abi.encodePacked(uint8(i)));
        }

        // Next one should fail
        vm.expectRevert("Max versions reached");
        persistor.setBlob(TEST_KEY, hex"FF");
    }

    function testBatchStorage() public {
        bytes32[] memory keys = new bytes32[](3);
        bytes[] memory data = new bytes[](3);

        keys[0] = keccak256("batch1");
        keys[1] = keccak256("batch2");
        keys[2] = keccak256("batch3");

        data[0] = hex"01";
        data[1] = hex"02";
        data[2] = hex"03";

        persistor.setBlobsBatch(keys, data);

        assertEq(persistor.getBlobCount(), 3);
        assertTrue(persistor.hasBlob(keys[0]));
        assertTrue(persistor.hasBlob(keys[1]));
        assertTrue(persistor.hasBlob(keys[2]));
    }

    function testBatchStorageSizeLimit() public {
        bytes32[] memory keys = new bytes32[](51);
        bytes[] memory data = new bytes[](51);

        for (uint256 i = 0; i < 51; i++) {
            keys[i] = keccak256(abi.encodePacked(i));
            data[i] = abi.encodePacked(uint8(i));
        }

        vm.expectRevert("Batch too large");
        persistor.setBlobsBatch(keys, data);
    }

    function testRemoveBlob() public {
        persistor.setBlob(TEST_KEY, TEST_DATA);
        assertTrue(persistor.hasBlob(TEST_KEY));

        persistor.removeBlob(TEST_KEY);
        assertFalse(persistor.hasBlob(TEST_KEY));
    }

    // ============ Signature Tests ============

    function testSignedBlobStorage() public {
        uint256 expiry = block.timestamp + 10 minutes;

        // Build signature
        bytes32 blobTypehash = keccak256("Blob(bytes32 key,bytes data,uint256 nonce,uint256 expiry)");
        bytes32 structHash = keccak256(
            abi.encode(
                blobTypehash,
                TEST_KEY,
                keccak256(TEST_DATA),
                0, // nonce
                expiry
            )
        );

        bytes32 domainSeparator = persistor.domainSeparatorV4();
        bytes32 digest = keccak256(abi.encodePacked("\x19\x01", domainSeparator, structHash));

        (uint8 v, bytes32 r, bytes32 s) = vm.sign(user1PrivateKey, digest);
        bytes memory signature = abi.encodePacked(r, s, v);

        // Store signed blob
        persistor.setSignedBlob(TEST_KEY, TEST_DATA, signature, user1, expiry);

        assertTrue(persistor.hasBlob(TEST_KEY));
        assertEq(persistor.nonces(user1), 1);
    }

    function testSignatureReplayPrevention() public {
        uint256 expiry = block.timestamp + 10 minutes;

        bytes32 blobTypehash = keccak256("Blob(bytes32 key,bytes data,uint256 nonce,uint256 expiry)");
        bytes32 structHash = keccak256(abi.encode(blobTypehash, TEST_KEY, keccak256(TEST_DATA), 0, expiry));

        bytes32 digest = keccak256(abi.encodePacked("\x19\x01", persistor.domainSeparatorV4(), structHash));

        (uint8 v, bytes32 r, bytes32 s) = vm.sign(user1PrivateKey, digest);
        bytes memory signature = abi.encodePacked(r, s, v);

        // First use - success
        persistor.setSignedBlob(TEST_KEY, TEST_DATA, signature, user1, expiry);

        // Nonce incremented, so replay fails with "Invalid signature"
        vm.expectRevert("Invalid signature");
        persistor.setSignedBlob(TEST_KEY, TEST_DATA, signature, user1, expiry);
    }

    function testExpiredSignature() public {
        uint256 expiry = block.timestamp - 1; // Already expired

        bytes32 structHash = keccak256(
            abi.encode(
                keccak256("Blob(bytes32 key,bytes data,uint256 nonce,uint256 expiry)"),
                TEST_KEY,
                keccak256(TEST_DATA),
                0,
                expiry
            )
        );

        bytes32 digest = keccak256(abi.encodePacked("\x19\x01", persistor.domainSeparatorV4(), structHash));

        (uint8 v, bytes32 r, bytes32 s) = vm.sign(user1PrivateKey, digest);
        bytes memory signature = abi.encodePacked(r, s, v);

        vm.expectRevert("Signature expired");
        persistor.setSignedBlob(TEST_KEY, TEST_DATA, signature, user1, expiry);
    }

    // ============ Pagination Tests ============

    function testPagination() public {
        // Create 10 documents
        for (uint256 i = 0; i < 10; i++) {
            bytes32 key = keccak256(abi.encodePacked("doc", i));
            persistor.setBlob(key, abi.encodePacked(uint8(i)));
        }

        // Test pagination
        (bytes32[] memory keys1,, uint256 total1) = persistor.getBlobsPaginated(0, 5);
        assertEq(keys1.length, 5);
        assertEq(total1, 10);

        (bytes32[] memory keys2,, uint256 total2) = persistor.getBlobsPaginated(5, 5);
        assertEq(keys2.length, 5);
        assertEq(total2, 10);

        (bytes32[] memory keys3,, uint256 total3) = persistor.getBlobsPaginated(8, 5);
        assertEq(keys3.length, 2); // Only 2 left
        assertEq(total3, 10);
    }

    function testPaginationWithAccessControl() public {
        bytes32 key1 = keccak256("doc1");
        bytes32 key2 = keccak256("doc2");

        persistor.setBlob(key1, TEST_DATA);
        persistor.setBlob(key2, TEST_DATA);

        // Grant user1 access to key1 only
        persistor.grantAccess(key1, user1);

        // User1 can see both keys but only decrypt key1
        vm.prank(user1);
        (bytes32[] memory keys, bytes[] memory values,) = persistor.getBlobsPaginated(0, 10);

        assertEq(keys.length, 2);
        // One of them should have data, one should be empty
        assertTrue(values[0].length > 0 || values[1].length > 0);
    }

    // ============ Utility Tests ============

    function testContentHashVerification() public {
        persistor.setBlob(TEST_KEY, TEST_DATA);

        assertTrue(persistor.verifyContentHash(TEST_KEY, TEST_DATA));
        assertFalse(persistor.verifyContentHash(TEST_KEY, hex"DEADBEEF"));
    }

    function testVersionString() public view {
        assertEq(persistor.version(), "1.0.0-simple");
    }

    function testGetAllKeys() public {
        bytes32 key1 = keccak256("key1");
        bytes32 key2 = keccak256("key2");

        persistor.setBlob(key1, hex"01");
        persistor.setBlob(key2, hex"02");

        bytes32[] memory keys = persistor.getAllKeys();
        assertEq(keys.length, 2);
    }

    function testGetKeyAtIndex() public {
        bytes32 key1 = keccak256("indexed1");
        bytes32 key2 = keccak256("indexed2");

        persistor.setBlob(key1, hex"01");
        persistor.setBlob(key2, hex"02");

        bytes32 firstKey = persistor.getKeyAtIndex(0);
        bytes32 secondKey = persistor.getKeyAtIndex(1);

        // One of the orderings should be true
        bool ordering1 = (firstKey == key1 && secondKey == key2);
        bool ordering2 = (firstKey == key2 && secondKey == key1);
        assertTrue(ordering1 || ordering2);

        vm.expectRevert("Index out of bounds");
        persistor.getKeyAtIndex(2);
    }

    // ============ CBOR Tests ============

    function testDecodeMapping() public {
        bytes32 key = keccak256("mapTest");
        bytes memory cborMap = hex"a16474657374657465737432"; // {"test": "test2"}

        persistor.setBlob(key, cborMap);

        (bytes[] memory keys, bytes[] memory values) = persistor.decodeMapping(key);
        assertEq(keys.length, 1);
        assertEq(values.length, 1);
        assertEq(string(keys[0]), "test");
        assertEq(string(values[0]), "test2");
    }

    function testDecodeArrayItem() public {
        bytes32 key = keccak256("arrayTest");
        bytes memory cborArray = hex"83656974656d31656974656d32656974656d33"; // ["item1", "item2", "item3"]

        persistor.setBlob(key, cborArray);

        bytes memory item0 = persistor.decodeArrayItem(key, 0);
        assertEq(string(item0), "item1");
    }

    // ============ Gas Tests ============

    function testGasSetBlob() public {
        uint256 gasBefore = gasleft();
        persistor.setBlob(TEST_KEY, TEST_DATA);
        uint256 gasUsed = gasBefore - gasleft();

        emit log_named_uint("Gas used for setBlob", gasUsed);
        assertTrue(gasUsed < 200000);
    }

    function testGasBatchStorage() public {
        bytes32[] memory keys = new bytes32[](10);
        bytes[] memory data = new bytes[](10);

        for (uint256 i = 0; i < 10; i++) {
            keys[i] = keccak256(abi.encodePacked(i));
            data[i] = TEST_DATA;
        }

        uint256 gasBefore = gasleft();
        persistor.setBlobsBatch(keys, data);
        uint256 gasUsed = gasBefore - gasleft();

        emit log_named_uint("Gas used for batch of 10", gasUsed);
        assertTrue(gasUsed < 1500000);
    }
}
