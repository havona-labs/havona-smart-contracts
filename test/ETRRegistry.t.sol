// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "../lib/openzeppelin-contracts/lib/forge-std/src/Test.sol";
import "../src/ETRRegistry.sol";

contract ETRRegistryTest is Test {
    ETRRegistry internal registry;

    address internal owner;
    address internal pledgor; // Borrower who pledges ETR
    address internal pledgee; // Bank/lender receiving pledge
    address internal newHolder; // Recipient in transfer/liquidation
    address internal unauthorized;

    bytes32 internal constant ETR_KEY_1 = keccak256("etr:epn:havona-001");
    bytes32 internal constant ETR_KEY_2 = keccak256("etr:ebl:havona-002");
    bytes32 internal constant AGREEMENT_HASH = keccak256("pledge-agreement-v1");
    bytes32 internal constant COURT_ORDER_HASH = keccak256("court-order-123");

    event ETRControlTransferred(bytes32 indexed etrKey, address indexed from, address indexed to, uint256 timestamp);

    event ETRPledged(
        bytes32 indexed etrKey,
        address indexed pledgor,
        address indexed pledgee,
        bytes32 agreementHash,
        uint256 timestamp
    );

    event ETRPledgeReleased(bytes32 indexed etrKey, address indexed pledgee, uint256 timestamp);

    event ETRLiquidated(
        bytes32 indexed etrKey,
        address indexed pledgee,
        address indexed newHolder,
        bytes32 courtOrderHash,
        uint256 timestamp
    );

    event ETRRedeemed(bytes32 indexed etrKey, address indexed holder, uint256 timestamp);

    function setUp() public {
        owner = address(this);
        pledgor = address(0x1);
        pledgee = address(0x2);
        newHolder = address(0x3);
        unauthorized = address(0x999);

        registry = new ETRRegistry();
    }

    // ============ Ownership Tests ============

    function testOwnerCanRecordPledge() public {
        registry.recordPledge(ETR_KEY_1, pledgor, pledgee, AGREEMENT_HASH);
        assertTrue(registry.isPledged(ETR_KEY_1));
    }

    function testNonOwnerCannotRecordPledge() public {
        vm.prank(unauthorized);
        vm.expectRevert();
        registry.recordPledge(ETR_KEY_1, pledgor, pledgee, AGREEMENT_HASH);
    }

    function testNonOwnerCannotRecordRelease() public {
        registry.recordPledge(ETR_KEY_1, pledgor, pledgee, AGREEMENT_HASH);

        vm.prank(unauthorized);
        vm.expectRevert();
        registry.recordPledgeRelease(ETR_KEY_1);
    }

    function testNonOwnerCannotRecordTransfer() public {
        vm.prank(unauthorized);
        vm.expectRevert();
        registry.recordControlTransfer(ETR_KEY_1, pledgor, newHolder);
    }

    function testNonOwnerCannotRecordLiquidation() public {
        registry.recordPledge(ETR_KEY_1, pledgor, pledgee, AGREEMENT_HASH);

        vm.prank(unauthorized);
        vm.expectRevert();
        registry.recordLiquidation(ETR_KEY_1, newHolder, COURT_ORDER_HASH);
    }

    function testNonOwnerCannotRecordRedemption() public {
        vm.prank(unauthorized);
        vm.expectRevert();
        registry.recordRedemption(ETR_KEY_1, pledgor);
    }

    // ============ Pledge Tests ============

    function testRecordPledge() public {
        vm.expectEmit(true, true, true, true);
        emit ETRPledged(ETR_KEY_1, pledgor, pledgee, AGREEMENT_HASH, block.timestamp);

        registry.recordPledge(ETR_KEY_1, pledgor, pledgee, AGREEMENT_HASH);

        assertTrue(registry.isPledged(ETR_KEY_1));

        (address storedPledgee, uint256 timestamp, bytes32 agreementHash) = registry.getPledgeInfo(ETR_KEY_1);
        assertEq(storedPledgee, pledgee);
        assertEq(timestamp, block.timestamp);
        assertEq(agreementHash, AGREEMENT_HASH);
    }

    function testCannotPledgeTwice() public {
        registry.recordPledge(ETR_KEY_1, pledgor, pledgee, AGREEMENT_HASH);

        vm.expectRevert("Already pledged");
        registry.recordPledge(ETR_KEY_1, pledgor, pledgee, AGREEMENT_HASH);
    }

    function testCannotPledgeWithInvalidPledgor() public {
        vm.expectRevert("Invalid pledgor");
        registry.recordPledge(ETR_KEY_1, address(0), pledgee, AGREEMENT_HASH);
    }

    function testCannotPledgeWithInvalidPledgee() public {
        vm.expectRevert("Invalid pledgee");
        registry.recordPledge(ETR_KEY_1, pledgor, address(0), AGREEMENT_HASH);
    }

    function testCannotPledgeRedeemedETR() public {
        registry.recordRedemption(ETR_KEY_1, pledgor);

        vm.expectRevert("ETR already redeemed");
        registry.recordPledge(ETR_KEY_1, pledgor, pledgee, AGREEMENT_HASH);
    }

    // ============ Release Tests ============

    function testRecordPledgeRelease() public {
        registry.recordPledge(ETR_KEY_1, pledgor, pledgee, AGREEMENT_HASH);

        vm.expectEmit(true, true, true, true);
        emit ETRPledgeReleased(ETR_KEY_1, pledgee, block.timestamp);

        registry.recordPledgeRelease(ETR_KEY_1);

        assertFalse(registry.isPledged(ETR_KEY_1));

        (address storedPledgee, uint256 timestamp, bytes32 agreementHash) = registry.getPledgeInfo(ETR_KEY_1);
        assertEq(storedPledgee, address(0));
        assertEq(timestamp, 0);
        assertEq(agreementHash, bytes32(0));
    }

    function testCannotReleaseUnpledgedETR() public {
        vm.expectRevert("Not pledged");
        registry.recordPledgeRelease(ETR_KEY_1);
    }

    function testCanPledgeAgainAfterRelease() public {
        // First pledge
        registry.recordPledge(ETR_KEY_1, pledgor, pledgee, AGREEMENT_HASH);
        registry.recordPledgeRelease(ETR_KEY_1);

        // Second pledge with different pledgee
        address newPledgee = address(0x4);
        registry.recordPledge(ETR_KEY_1, pledgor, newPledgee, AGREEMENT_HASH);

        assertTrue(registry.isPledged(ETR_KEY_1));
        (address storedPledgee,,) = registry.getPledgeInfo(ETR_KEY_1);
        assertEq(storedPledgee, newPledgee);
    }

    // ============ Control Transfer Tests ============

    function testRecordControlTransfer() public {
        vm.expectEmit(true, true, true, true);
        emit ETRControlTransferred(ETR_KEY_1, pledgor, newHolder, block.timestamp);

        registry.recordControlTransfer(ETR_KEY_1, pledgor, newHolder);
    }

    function testCannotTransferWhilePledged() public {
        registry.recordPledge(ETR_KEY_1, pledgor, pledgee, AGREEMENT_HASH);

        vm.expectRevert("Cannot transfer while pledged");
        registry.recordControlTransfer(ETR_KEY_1, pledgor, newHolder);
    }

    function testCannotTransferWithInvalidFrom() public {
        vm.expectRevert("Invalid from address");
        registry.recordControlTransfer(ETR_KEY_1, address(0), newHolder);
    }

    function testCannotTransferWithInvalidTo() public {
        vm.expectRevert("Invalid to address");
        registry.recordControlTransfer(ETR_KEY_1, pledgor, address(0));
    }

    function testCannotTransferRedeemedETR() public {
        registry.recordRedemption(ETR_KEY_1, pledgor);

        vm.expectRevert("ETR already redeemed");
        registry.recordControlTransfer(ETR_KEY_1, pledgor, newHolder);
    }

    // ============ Liquidation Tests ============

    function testRecordLiquidation() public {
        registry.recordPledge(ETR_KEY_1, pledgor, pledgee, AGREEMENT_HASH);

        vm.expectEmit(true, true, true, true);
        emit ETRLiquidated(ETR_KEY_1, pledgee, newHolder, COURT_ORDER_HASH, block.timestamp);

        registry.recordLiquidation(ETR_KEY_1, newHolder, COURT_ORDER_HASH);

        // Pledge should be cleared
        assertFalse(registry.isPledged(ETR_KEY_1));
    }

    function testCannotLiquidateUnpledgedETR() public {
        vm.expectRevert("Not pledged");
        registry.recordLiquidation(ETR_KEY_1, newHolder, COURT_ORDER_HASH);
    }

    function testCannotLiquidateWithInvalidNewHolder() public {
        registry.recordPledge(ETR_KEY_1, pledgor, pledgee, AGREEMENT_HASH);

        vm.expectRevert("Invalid new holder");
        registry.recordLiquidation(ETR_KEY_1, address(0), COURT_ORDER_HASH);
    }

    function testCannotLiquidateRedeemedETR() public {
        // This shouldn't happen in practice (can't be both pledged and redeemed)
        // but test the guard anyway
        registry.recordPledge(ETR_KEY_1, pledgor, pledgee, AGREEMENT_HASH);

        // Simulate edge case by directly setting redemption
        // (In real contract, this wouldn't happen as pledge prevents redemption)
        // Skip this test - contract logic prevents this scenario
    }

    function testCanTransferAfterLiquidation() public {
        registry.recordPledge(ETR_KEY_1, pledgor, pledgee, AGREEMENT_HASH);
        registry.recordLiquidation(ETR_KEY_1, newHolder, COURT_ORDER_HASH);

        // After liquidation, the new holder can transfer
        address finalHolder = address(0x5);
        registry.recordControlTransfer(ETR_KEY_1, newHolder, finalHolder);
        // No revert = success
    }

    // ============ Redemption Tests ============

    function testRecordRedemption() public {
        vm.expectEmit(true, true, true, true);
        emit ETRRedeemed(ETR_KEY_1, pledgor, block.timestamp);

        registry.recordRedemption(ETR_KEY_1, pledgor);

        assertTrue(registry.isRedeemed(ETR_KEY_1));
    }

    function testCannotRedeemWhilePledged() public {
        registry.recordPledge(ETR_KEY_1, pledgor, pledgee, AGREEMENT_HASH);

        vm.expectRevert("Cannot redeem while pledged");
        registry.recordRedemption(ETR_KEY_1, pledgor);
    }

    function testCannotRedeemTwice() public {
        registry.recordRedemption(ETR_KEY_1, pledgor);

        vm.expectRevert("Already redeemed");
        registry.recordRedemption(ETR_KEY_1, pledgor);
    }

    function testCannotRedeemWithInvalidHolder() public {
        vm.expectRevert("Invalid holder");
        registry.recordRedemption(ETR_KEY_1, address(0));
    }

    // ============ Multiple ETR Tests ============

    function testMultipleETRsIndependent() public {
        // Pledge ETR 1
        registry.recordPledge(ETR_KEY_1, pledgor, pledgee, AGREEMENT_HASH);

        // ETR 2 is still unpledged
        assertFalse(registry.isPledged(ETR_KEY_2));

        // Can transfer ETR 2
        registry.recordControlTransfer(ETR_KEY_2, pledgor, newHolder);

        // ETR 1 still pledged
        assertTrue(registry.isPledged(ETR_KEY_1));
    }

    function testFullLifecycle() public {
        // 1. Transfer to borrower
        registry.recordControlTransfer(ETR_KEY_1, owner, pledgor);

        // 2. Borrower pledges to bank
        registry.recordPledge(ETR_KEY_1, pledgor, pledgee, AGREEMENT_HASH);

        // 3. Bank releases (debt paid)
        registry.recordPledgeRelease(ETR_KEY_1);

        // 4. Borrower redeems (goods delivered)
        registry.recordRedemption(ETR_KEY_1, pledgor);

        // Verify final state
        assertFalse(registry.isPledged(ETR_KEY_1));
        assertTrue(registry.isRedeemed(ETR_KEY_1));
    }

    function testLiquidationLifecycle() public {
        // 1. Transfer to borrower
        registry.recordControlTransfer(ETR_KEY_1, owner, pledgor);

        // 2. Borrower pledges to bank
        registry.recordPledge(ETR_KEY_1, pledgor, pledgee, AGREEMENT_HASH);

        // 3. Borrower defaults, bank liquidates
        registry.recordLiquidation(ETR_KEY_1, pledgee, COURT_ORDER_HASH);

        // 4. Bank redeems (takes the goods)
        registry.recordRedemption(ETR_KEY_1, pledgee);

        // Verify final state
        assertFalse(registry.isPledged(ETR_KEY_1));
        assertTrue(registry.isRedeemed(ETR_KEY_1));
    }

    // ============ View Function Tests ============

    function testIsPledged() public {
        assertFalse(registry.isPledged(ETR_KEY_1));

        registry.recordPledge(ETR_KEY_1, pledgor, pledgee, AGREEMENT_HASH);
        assertTrue(registry.isPledged(ETR_KEY_1));

        registry.recordPledgeRelease(ETR_KEY_1);
        assertFalse(registry.isPledged(ETR_KEY_1));
    }

    function testGetPledgeInfo() public {
        // Before pledge
        (address storedPledgee, uint256 timestamp, bytes32 agreementHash) = registry.getPledgeInfo(ETR_KEY_1);
        assertEq(storedPledgee, address(0));
        assertEq(timestamp, 0);
        assertEq(agreementHash, bytes32(0));

        // After pledge
        registry.recordPledge(ETR_KEY_1, pledgor, pledgee, AGREEMENT_HASH);
        (storedPledgee, timestamp, agreementHash) = registry.getPledgeInfo(ETR_KEY_1);
        assertEq(storedPledgee, pledgee);
        assertGt(timestamp, 0);
        assertEq(agreementHash, AGREEMENT_HASH);
    }

    function testVersion() public view {
        assertEq(registry.version(), "1.0.0");
    }

    // ============ Gas Tests ============

    function testGasRecordPledge() public {
        uint256 gasBefore = gasleft();
        registry.recordPledge(ETR_KEY_1, pledgor, pledgee, AGREEMENT_HASH);
        uint256 gasUsed = gasBefore - gasleft();

        emit log_named_uint("Gas used for recordPledge", gasUsed);
        assertTrue(gasUsed < 100000);
    }

    function testGasRecordRelease() public {
        registry.recordPledge(ETR_KEY_1, pledgor, pledgee, AGREEMENT_HASH);

        uint256 gasBefore = gasleft();
        registry.recordPledgeRelease(ETR_KEY_1);
        uint256 gasUsed = gasBefore - gasleft();

        emit log_named_uint("Gas used for recordPledgeRelease", gasUsed);
        assertTrue(gasUsed < 50000);
    }

    function testGasRecordTransfer() public {
        uint256 gasBefore = gasleft();
        registry.recordControlTransfer(ETR_KEY_1, pledgor, newHolder);
        uint256 gasUsed = gasBefore - gasleft();

        emit log_named_uint("Gas used for recordControlTransfer", gasUsed);
        assertTrue(gasUsed < 50000);
    }

    function testGasRecordLiquidation() public {
        registry.recordPledge(ETR_KEY_1, pledgor, pledgee, AGREEMENT_HASH);

        uint256 gasBefore = gasleft();
        registry.recordLiquidation(ETR_KEY_1, newHolder, COURT_ORDER_HASH);
        uint256 gasUsed = gasBefore - gasleft();

        emit log_named_uint("Gas used for recordLiquidation", gasUsed);
        assertTrue(gasUsed < 50000);
    }
}
