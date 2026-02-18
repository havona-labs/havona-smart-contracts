// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "../lib/openzeppelin-contracts/lib/forge-std/src/Test.sol";
import "../src/HavonaAgentRegistry.sol";
import "../src/HavonaAgentReputation.sol";

contract HavonaAgentRegistryTest is Test {
    HavonaAgentRegistry internal registry;
    HavonaAgentReputation internal reputation;

    address internal owner;
    address internal unauthorized;
    address internal wallet1;
    address internal wallet2;

    uint256 internal signerKey;
    address internal signerAddr;

    string internal constant AGENT_URI = "https://api.havona.com/agents/blotting/metadata.json";
    string internal constant AGENT_URI_2 = "https://api.havona.com/agents/compliance/metadata.json";

    // Events (must redeclare for vm.expectEmit)
    event AgentRegistered(uint256 indexed agentId, address indexed wallet, string agentURI);
    event AgentWalletUpdated(uint256 indexed agentId, address indexed oldWallet, address indexed newWallet);
    event AgentDeactivated(uint256 indexed agentId);
    event AgentReactivated(uint256 indexed agentId);
    event FeedbackSubmitted(
        uint256 indexed agentId,
        address indexed client,
        int128 value,
        uint8 valueDecimals,
        bytes32 indexed tag1,
        bytes32 tag2,
        uint256 feedbackIndex
    );
    event FeedbackRevoked(uint256 indexed agentId, uint256 indexed feedbackIndex);

    function setUp() public {
        owner = address(this);
        unauthorized = address(0x999);
        wallet1 = address(0x1);
        wallet2 = address(0x2);

        // Create a proper signer keypair for EIP-712 tests
        signerKey = 0xA11CE;
        signerAddr = vm.addr(signerKey);

        registry = new HavonaAgentRegistry();
        reputation = new HavonaAgentReputation();
    }

    // ============================================================
    //                    IDENTITY REGISTRY TESTS
    // ============================================================

    // --- Registration ---

    function testRegisterAgent() public {
        vm.expectEmit(true, true, false, true);
        emit AgentRegistered(1, wallet1, AGENT_URI);

        uint256 agentId = registry.register(AGENT_URI, wallet1);

        assertEq(agentId, 1);
        assertEq(registry.totalAgents(), 1);
        assertEq(registry.getAgentWallet(agentId), wallet1);
        assertTrue(registry.isActive(agentId));
        assertEq(registry.tokenURI(agentId), AGENT_URI);
    }

    function testRegisterMultipleAgents() public {
        uint256 id1 = registry.register(AGENT_URI, wallet1);
        uint256 id2 = registry.register(AGENT_URI_2, wallet2);

        assertEq(id1, 1);
        assertEq(id2, 2);
        assertEq(registry.totalAgents(), 2);
        assertEq(registry.getAgentWallet(id1), wallet1);
        assertEq(registry.getAgentWallet(id2), wallet2);
    }

    function testCannotRegisterWithZeroWallet() public {
        vm.expectRevert("Invalid wallet");
        registry.register(AGENT_URI, address(0));
    }

    function testCannotRegisterWithEmptyURI() public {
        vm.expectRevert("Empty URI");
        registry.register("", wallet1);
    }

    function testNonOwnerCannotRegister() public {
        vm.prank(unauthorized);
        vm.expectRevert();
        registry.register(AGENT_URI, wallet1);
    }

    // --- URI Update ---

    function testSetAgentURI() public {
        uint256 agentId = registry.register(AGENT_URI, wallet1);
        registry.setAgentURI(agentId, AGENT_URI_2);
        assertEq(registry.tokenURI(agentId), AGENT_URI_2);
    }

    function testCannotSetEmptyURI() public {
        uint256 agentId = registry.register(AGENT_URI, wallet1);
        vm.expectRevert("Empty URI");
        registry.setAgentURI(agentId, "");
    }

    function testCannotSetURIForNonexistentAgent() public {
        vm.expectRevert();
        registry.setAgentURI(999, AGENT_URI);
    }

    function testNonOwnerCannotSetURI() public {
        uint256 agentId = registry.register(AGENT_URI, wallet1);
        vm.prank(unauthorized);
        vm.expectRevert();
        registry.setAgentURI(agentId, AGENT_URI_2);
    }

    // --- Wallet Update (EIP-712) ---

    function testSetAgentWalletWithSignature() public {
        uint256 agentId = registry.register(AGENT_URI, signerAddr);

        uint256 deadline = block.timestamp + 1 hours;
        uint256 nonce = registry.nonces(signerAddr);

        bytes32 structHash = keccak256(abi.encode(registry.SET_WALLET_TYPEHASH(), agentId, wallet2, nonce, deadline));

        bytes32 domainSeparator = _getDomainSeparator();
        bytes32 digest = keccak256(abi.encodePacked("\x19\x01", domainSeparator, structHash));

        (uint8 v, bytes32 r, bytes32 s) = vm.sign(signerKey, digest);
        bytes memory signature = abi.encodePacked(r, s, v);

        vm.expectEmit(true, true, true, true);
        emit AgentWalletUpdated(agentId, signerAddr, wallet2);

        registry.setAgentWallet(agentId, wallet2, deadline, signature);

        assertEq(registry.getAgentWallet(agentId), wallet2);
    }

    function testCannotSetWalletWithExpiredDeadline() public {
        uint256 agentId = registry.register(AGENT_URI, signerAddr);
        uint256 deadline = block.timestamp - 1;

        bytes memory dummySig = new bytes(65);
        vm.expectRevert("Signature expired");
        registry.setAgentWallet(agentId, wallet2, deadline, dummySig);
    }

    function testCannotSetWalletToZeroAddress() public {
        uint256 agentId = registry.register(AGENT_URI, signerAddr);
        uint256 deadline = block.timestamp + 1 hours;

        bytes memory dummySig = new bytes(65);
        vm.expectRevert("Invalid wallet");
        registry.setAgentWallet(agentId, address(0), deadline, dummySig);
    }

    function testCannotSetWalletWithWrongSigner() public {
        uint256 agentId = registry.register(AGENT_URI, signerAddr);

        uint256 deadline = block.timestamp + 1 hours;
        uint256 nonce = registry.nonces(signerAddr);

        bytes32 structHash = keccak256(abi.encode(registry.SET_WALLET_TYPEHASH(), agentId, wallet2, nonce, deadline));

        bytes32 domainSeparator = _getDomainSeparator();
        bytes32 digest = keccak256(abi.encodePacked("\x19\x01", domainSeparator, structHash));

        // Sign with a DIFFERENT key
        uint256 wrongKey = 0xBAD;
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(wrongKey, digest);
        bytes memory signature = abi.encodePacked(r, s, v);

        vm.expectRevert("Invalid signature");
        registry.setAgentWallet(agentId, wallet2, deadline, signature);
    }

    function testNonceIncrementsAfterWalletUpdate() public {
        uint256 agentId = registry.register(AGENT_URI, signerAddr);

        assertEq(registry.nonces(signerAddr), 0);

        // First wallet update
        _signAndSetWallet(agentId, signerAddr, signerKey, wallet2, 0);

        assertEq(registry.nonces(signerAddr), 1);
    }

    // --- Deactivate / Reactivate ---

    function testDeactivateAgent() public {
        uint256 agentId = registry.register(AGENT_URI, wallet1);

        vm.expectEmit(true, false, false, true);
        emit AgentDeactivated(agentId);

        registry.deactivate(agentId);
        assertFalse(registry.isActive(agentId));
    }

    function testReactivateAgent() public {
        uint256 agentId = registry.register(AGENT_URI, wallet1);
        registry.deactivate(agentId);

        vm.expectEmit(true, false, false, true);
        emit AgentReactivated(agentId);

        registry.reactivate(agentId);
        assertTrue(registry.isActive(agentId));
    }

    function testCannotDeactivateAlreadyInactive() public {
        uint256 agentId = registry.register(AGENT_URI, wallet1);
        registry.deactivate(agentId);

        vm.expectRevert("Already inactive");
        registry.deactivate(agentId);
    }

    function testCannotReactivateAlreadyActive() public {
        uint256 agentId = registry.register(AGENT_URI, wallet1);

        vm.expectRevert("Already active");
        registry.reactivate(agentId);
    }

    function testNonOwnerCannotDeactivate() public {
        uint256 agentId = registry.register(AGENT_URI, wallet1);
        vm.prank(unauthorized);
        vm.expectRevert();
        registry.deactivate(agentId);
    }

    function testNonOwnerCannotReactivate() public {
        uint256 agentId = registry.register(AGENT_URI, wallet1);
        registry.deactivate(agentId);
        vm.prank(unauthorized);
        vm.expectRevert();
        registry.reactivate(agentId);
    }

    // --- View Functions ---

    function testTotalAgentsStartsAtZero() public view {
        assertEq(registry.totalAgents(), 0);
    }

    function testVersion() public view {
        assertEq(registry.version(), "1.0.0");
    }

    // ============================================================
    //                   REPUTATION REGISTRY TESTS
    // ============================================================

    bytes32 internal constant TAG_ORACLE = keccak256("oracle_accuracy");
    bytes32 internal constant TAG_DCSA = keccak256("dcsa_adapter");
    bytes32 internal constant TAG_TRADE = keccak256("trade_execution");
    bytes32 internal constant TAG_BLOTTING = keccak256("blotting_agent");

    // --- Feedback Submission ---

    function testGiveFeedback() public {
        uint256 agentId = 1;

        uint256 idx =
            reputation.giveFeedback(agentId, wallet1, 85, 0, TAG_ORACLE, TAG_DCSA, "/api/oracle", "", bytes32(0));

        assertEq(idx, 0);
        assertEq(reputation.getFeedbackCount(agentId), 1);

        (address client, int128 value, uint8 decimals, bytes32 t1, bytes32 t2, uint256 ts, bool revoked) =
            reputation.getFeedback(agentId, 0);

        assertEq(client, wallet1);
        assertEq(value, 85);
        assertEq(decimals, 0);
        assertEq(t1, TAG_ORACLE);
        assertEq(t2, TAG_DCSA);
        assertGt(ts, 0);
        assertFalse(revoked);
    }

    function testGiveMultipleFeedback() public {
        uint256 agentId = 1;

        reputation.giveFeedback(agentId, wallet1, 90, 0, TAG_ORACLE, TAG_DCSA, "", "", bytes32(0));
        reputation.giveFeedback(agentId, wallet2, 75, 0, TAG_ORACLE, TAG_DCSA, "", "", bytes32(0));
        reputation.giveFeedback(agentId, wallet1, 60, 0, TAG_TRADE, TAG_BLOTTING, "", "", bytes32(0));

        assertEq(reputation.getFeedbackCount(agentId), 3);
    }

    function testCannotGiveFeedbackWithInvalidClient() public {
        vm.expectRevert("Invalid client");
        reputation.giveFeedback(1, address(0), 85, 0, TAG_ORACLE, TAG_DCSA, "", "", bytes32(0));
    }

    function testCannotGiveFeedbackWithExcessiveDecimals() public {
        vm.expectRevert("Decimals exceed 18");
        reputation.giveFeedback(1, wallet1, 85, 19, TAG_ORACLE, TAG_DCSA, "", "", bytes32(0));
    }

    function testNonOwnerCannotGiveFeedback() public {
        vm.prank(unauthorized);
        vm.expectRevert();
        reputation.giveFeedback(1, wallet1, 85, 0, TAG_ORACLE, TAG_DCSA, "", "", bytes32(0));
    }

    function testFeedbackWithOffchainData() public {
        bytes32 reportHash = keccak256("detailed-report-v1");

        reputation.giveFeedback(
            1, wallet1, 92, 2, TAG_ORACLE, TAG_DCSA, "/api/oracle/dcsa", "ipfs://QmReport123", reportHash
        );

        assertEq(reputation.getFeedbackCount(1), 1);
    }

    // --- Feedback Revocation ---

    function testRevokeFeedback() public {
        reputation.giveFeedback(1, wallet1, 85, 0, TAG_ORACLE, TAG_DCSA, "", "", bytes32(0));

        vm.expectEmit(true, true, false, true);
        emit FeedbackRevoked(1, 0);

        reputation.revokeFeedback(1, 0);

        (,,,,,, bool revoked) = reputation.getFeedback(1, 0);
        assertTrue(revoked);
    }

    function testCannotRevokeAlreadyRevoked() public {
        reputation.giveFeedback(1, wallet1, 85, 0, TAG_ORACLE, TAG_DCSA, "", "", bytes32(0));
        reputation.revokeFeedback(1, 0);

        vm.expectRevert("Already revoked");
        reputation.revokeFeedback(1, 0);
    }

    function testCannotRevokeOutOfBounds() public {
        vm.expectRevert("Index out of bounds");
        reputation.revokeFeedback(1, 0);
    }

    function testNonOwnerCannotRevoke() public {
        reputation.giveFeedback(1, wallet1, 85, 0, TAG_ORACLE, TAG_DCSA, "", "", bytes32(0));

        vm.prank(unauthorized);
        vm.expectRevert();
        reputation.revokeFeedback(1, 0);
    }

    // --- Summary Aggregation ---

    function testGetSummaryAllFeedback() public {
        reputation.giveFeedback(1, wallet1, 90, 0, TAG_ORACLE, TAG_DCSA, "", "", bytes32(0));
        reputation.giveFeedback(1, wallet2, 80, 0, TAG_ORACLE, TAG_DCSA, "", "", bytes32(0));

        address[] memory clients = new address[](0);
        (uint256 count, int256 total, uint8 decimals) = reputation.getSummary(1, clients, TAG_ORACLE, TAG_DCSA);

        assertEq(count, 2);
        assertEq(total, 170);
        assertEq(decimals, 0);
    }

    function testGetSummaryFilterByClient() public {
        reputation.giveFeedback(1, wallet1, 90, 0, TAG_ORACLE, TAG_DCSA, "", "", bytes32(0));
        reputation.giveFeedback(1, wallet2, 80, 0, TAG_ORACLE, TAG_DCSA, "", "", bytes32(0));

        address[] memory clients = new address[](1);
        clients[0] = wallet1;
        (uint256 count, int256 total,) = reputation.getSummary(1, clients, TAG_ORACLE, TAG_DCSA);

        assertEq(count, 1);
        assertEq(total, 90);
    }

    function testGetSummaryFilterByTag() public {
        reputation.giveFeedback(1, wallet1, 90, 0, TAG_ORACLE, TAG_DCSA, "", "", bytes32(0));
        reputation.giveFeedback(1, wallet1, 60, 0, TAG_TRADE, TAG_BLOTTING, "", "", bytes32(0));

        address[] memory clients = new address[](0);
        (uint256 count, int256 total,) = reputation.getSummary(1, clients, TAG_ORACLE, bytes32(0));

        assertEq(count, 1);
        assertEq(total, 90);
    }

    function testGetSummaryExcludesRevoked() public {
        reputation.giveFeedback(1, wallet1, 90, 0, TAG_ORACLE, TAG_DCSA, "", "", bytes32(0));
        reputation.giveFeedback(1, wallet2, 10, 0, TAG_ORACLE, TAG_DCSA, "", "", bytes32(0));
        reputation.revokeFeedback(1, 1); // Revoke the 10-score feedback

        address[] memory clients = new address[](0);
        (uint256 count, int256 total,) = reputation.getSummary(1, clients, TAG_ORACLE, TAG_DCSA);

        assertEq(count, 1);
        assertEq(total, 90);
    }

    function testGetSummaryNegativeValues() public {
        reputation.giveFeedback(1, wallet1, -50, 0, TAG_ORACLE, TAG_DCSA, "", "", bytes32(0));
        reputation.giveFeedback(1, wallet2, 100, 0, TAG_ORACLE, TAG_DCSA, "", "", bytes32(0));

        address[] memory clients = new address[](0);
        (uint256 count, int256 total,) = reputation.getSummary(1, clients, TAG_ORACLE, TAG_DCSA);

        assertEq(count, 2);
        assertEq(total, 50);
    }

    function testGetSummaryEmpty() public view {
        address[] memory clients = new address[](0);
        (uint256 count, int256 total,) = reputation.getSummary(999, clients, TAG_ORACLE, TAG_DCSA);

        assertEq(count, 0);
        assertEq(total, 0);
    }

    // --- Reputation Version ---

    function testReputationVersion() public view {
        assertEq(reputation.version(), "1.0.0");
    }

    // ============================================================
    //                      GAS BENCHMARKS
    // ============================================================

    function testGasRegisterAgent() public {
        uint256 gasBefore = gasleft();
        registry.register(AGENT_URI, wallet1);
        uint256 gasUsed = gasBefore - gasleft();

        emit log_named_uint("Gas: register agent", gasUsed);
        assertTrue(gasUsed < 300000); // ERC-721 mint + URI storage
    }

    function testGasGiveFeedback() public {
        uint256 gasBefore = gasleft();
        reputation.giveFeedback(1, wallet1, 85, 0, TAG_ORACLE, TAG_DCSA, "", "", bytes32(0));
        uint256 gasUsed = gasBefore - gasleft();

        emit log_named_uint("Gas: give feedback", gasUsed);
        assertTrue(gasUsed < 200000);
    }

    function testGasDeactivateAgent() public {
        registry.register(AGENT_URI, wallet1);

        uint256 gasBefore = gasleft();
        registry.deactivate(1);
        uint256 gasUsed = gasBefore - gasleft();

        emit log_named_uint("Gas: deactivate agent", gasUsed);
        assertTrue(gasUsed < 50000);
    }

    // ============================================================
    //                    FULL LIFECYCLE TEST
    // ============================================================

    function testFullAgentLifecycle() public {
        // 1. Register agent
        uint256 agentId = registry.register(AGENT_URI, signerAddr);
        assertEq(agentId, 1);
        assertTrue(registry.isActive(agentId));

        // 2. Submit reputation feedback
        reputation.giveFeedback(agentId, wallet1, 95, 0, TAG_ORACLE, TAG_DCSA, "", "", bytes32(0));
        reputation.giveFeedback(agentId, wallet2, 88, 0, TAG_ORACLE, TAG_DCSA, "", "", bytes32(0));

        // 3. Check reputation
        address[] memory clients = new address[](0);
        (uint256 count, int256 total,) = reputation.getSummary(agentId, clients, TAG_ORACLE, TAG_DCSA);
        assertEq(count, 2);
        assertEq(total, 183);

        // 4. Update metadata
        registry.setAgentURI(agentId, AGENT_URI_2);
        assertEq(registry.tokenURI(agentId), AGENT_URI_2);

        // 5. Rotate wallet via EIP-712
        _signAndSetWallet(agentId, signerAddr, signerKey, wallet2, 0);
        assertEq(registry.getAgentWallet(agentId), wallet2);

        // 6. Deactivate
        registry.deactivate(agentId);
        assertFalse(registry.isActive(agentId));

        // 7. Reactivate
        registry.reactivate(agentId);
        assertTrue(registry.isActive(agentId));
    }

    // ============================================================
    //                       HELPERS
    // ============================================================

    function _getDomainSeparator() internal view returns (bytes32) {
        bytes32 typeHash =
            keccak256("EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)");
        return keccak256(
            abi.encode(typeHash, keccak256("HavonaAgentRegistry"), keccak256("1"), block.chainid, address(registry))
        );
    }

    function _signAndSetWallet(uint256 agentId, address, uint256 currentKey, address newWallet, uint256 nonce)
        internal
    {
        uint256 deadline = block.timestamp + 1 hours;

        bytes32 structHash = keccak256(abi.encode(registry.SET_WALLET_TYPEHASH(), agentId, newWallet, nonce, deadline));

        bytes32 domainSeparator = _getDomainSeparator();
        bytes32 digest = keccak256(abi.encodePacked("\x19\x01", domainSeparator, structHash));

        (uint8 v, bytes32 r, bytes32 s) = vm.sign(currentKey, digest);
        bytes memory signature = abi.encodePacked(r, s, v);

        registry.setAgentWallet(agentId, newWallet, deadline, signature);
    }
}
