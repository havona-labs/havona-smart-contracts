// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

/**
 * @title ETRRegistry
 * @notice ETR lifecycle event registry for MLETR-compliant audit trails
 * @dev Companion contract to HavonaPersistor - emits business events, minimal state
 *
 * KEY PRINCIPLES:
 * - HavonaPersistor stores CBOR blob data (source of truth for content)
 * - ETRRegistry emits semantic events (pledge, transfer, liquidation)
 * - Events are indexed for external auditors and banks
 * - Minimal on-chain state (pledge status only)
 * - Future path to ERC-721 tokens if needed
 *
 * MLETR COMPLIANCE:
 * - Article 10: Control = functional equivalent of possession
 * - Pledgee identity must be verifiable (included in events)
 * - Procedural formalities for enforcement (liquidation events)
 * - Long-term data preservation via immutable event logs
 *
 * @custom:security-contact security@havona.io
 * @custom:version 1.0.0
 */
contract ETRRegistry is Ownable, ReentrancyGuard {
    // ============ Storage ============

    /// @notice Pledge status tracking (minimal state)
    struct PledgeInfo {
        address pledgee; // Bank/lender address
        uint256 timestamp; // When pledge was created
        bytes32 agreementHash; // Hash of pledge agreement document
    }

    /// @notice Active pledges by ETR key
    mapping(bytes32 => PledgeInfo) public pledgeStatus;

    /// @notice Redeemed ETRs (goods delivered, ETR burned)
    mapping(bytes32 => bool) public isRedeemed;

    // ============ Events ============

    /**
     * @notice Emitted when ETR control/ownership transfers
     * @param etrKey The ETR identifier (same key used in HavonaPersistor)
     * @param from Previous holder address
     * @param to New holder address
     * @param timestamp Block timestamp of transfer
     */
    event ETRControlTransferred(bytes32 indexed etrKey, address indexed from, address indexed to, uint256 timestamp);

    /**
     * @notice Emitted when ETR is pledged as collateral
     * @param etrKey The ETR identifier
     * @param pledgor Borrower who pledges the ETR
     * @param pledgee Bank/lender receiving the pledge
     * @param agreementHash Hash of the pledge agreement document
     * @param timestamp Block timestamp of pledge
     */
    event ETRPledged(
        bytes32 indexed etrKey,
        address indexed pledgor,
        address indexed pledgee,
        bytes32 agreementHash,
        uint256 timestamp
    );

    /**
     * @notice Emitted when pledge is released (debt paid)
     * @param etrKey The ETR identifier
     * @param pledgee Bank/lender releasing the pledge
     * @param timestamp Block timestamp of release
     */
    event ETRPledgeReleased(bytes32 indexed etrKey, address indexed pledgee, uint256 timestamp);

    /**
     * @notice Emitted when pledgee liquidates defaulted collateral
     * @param etrKey The ETR identifier
     * @param pledgee Bank/lender executing liquidation
     * @param newHolder Recipient of liquidated ETR (bank or liquidator)
     * @param courtOrderHash Hash of court order or enforcement document
     * @param timestamp Block timestamp of liquidation
     */
    event ETRLiquidated(
        bytes32 indexed etrKey,
        address indexed pledgee,
        address indexed newHolder,
        bytes32 courtOrderHash,
        uint256 timestamp
    );

    /**
     * @notice Emitted when ETR is redeemed (goods delivered)
     * @param etrKey The ETR identifier
     * @param holder Final holder at time of redemption
     * @param timestamp Block timestamp of redemption
     */
    event ETRRedeemed(bytes32 indexed etrKey, address indexed holder, uint256 timestamp);

    // ============ Constructor ============

    constructor() Ownable(msg.sender) {}

    // ============ State Mutation Functions ============

    /**
     * @notice Record a pledge of ETR as collateral
     * @param etrKey The ETR identifier
     * @param pledgor Borrower address
     * @param pledgee Bank/lender address
     * @param agreementHash Hash of pledge agreement
     * @dev Only callable by Havona server (owner)
     */
    function recordPledge(bytes32 etrKey, address pledgor, address pledgee, bytes32 agreementHash)
        external
        onlyOwner
        nonReentrant
    {
        require(pledgor != address(0), "Invalid pledgor");
        require(pledgee != address(0), "Invalid pledgee");
        require(pledgeStatus[etrKey].pledgee == address(0), "Already pledged");
        require(!isRedeemed[etrKey], "ETR already redeemed");

        pledgeStatus[etrKey] = PledgeInfo({pledgee: pledgee, timestamp: block.timestamp, agreementHash: agreementHash});

        emit ETRPledged(etrKey, pledgor, pledgee, agreementHash, block.timestamp);
    }

    /**
     * @notice Record release of a pledge
     * @param etrKey The ETR identifier
     * @dev Only callable by Havona server (owner)
     */
    function recordPledgeRelease(bytes32 etrKey) external onlyOwner nonReentrant {
        PledgeInfo storage pledge = pledgeStatus[etrKey];
        require(pledge.pledgee != address(0), "Not pledged");

        address releasingPledgee = pledge.pledgee;

        // Clear pledge state
        delete pledgeStatus[etrKey];

        emit ETRPledgeReleased(etrKey, releasingPledgee, block.timestamp);
    }

    /**
     * @notice Record liquidation of pledged ETR
     * @param etrKey The ETR identifier
     * @param newHolder Recipient of liquidated ETR
     * @param courtOrderHash Hash of enforcement documentation
     * @dev Only callable by Havona server (owner)
     */
    function recordLiquidation(bytes32 etrKey, address newHolder, bytes32 courtOrderHash)
        external
        onlyOwner
        nonReentrant
    {
        PledgeInfo storage pledge = pledgeStatus[etrKey];
        require(pledge.pledgee != address(0), "Not pledged");
        require(newHolder != address(0), "Invalid new holder");
        require(!isRedeemed[etrKey], "ETR already redeemed");

        address liquidatingPledgee = pledge.pledgee;

        // Clear pledge state (now owned by newHolder)
        delete pledgeStatus[etrKey];

        emit ETRLiquidated(etrKey, liquidatingPledgee, newHolder, courtOrderHash, block.timestamp);
    }

    /**
     * @notice Record transfer of ETR control
     * @param etrKey The ETR identifier
     * @param from Previous holder
     * @param to New holder
     * @dev Only callable by Havona server (owner)
     */
    function recordControlTransfer(bytes32 etrKey, address from, address to) external onlyOwner nonReentrant {
        require(from != address(0), "Invalid from address");
        require(to != address(0), "Invalid to address");
        require(pledgeStatus[etrKey].pledgee == address(0), "Cannot transfer while pledged");
        require(!isRedeemed[etrKey], "ETR already redeemed");

        emit ETRControlTransferred(etrKey, from, to, block.timestamp);
    }

    /**
     * @notice Record redemption of ETR (goods delivered)
     * @param etrKey The ETR identifier
     * @param holder Holder at time of redemption
     * @dev Only callable by Havona server (owner)
     */
    function recordRedemption(bytes32 etrKey, address holder) external onlyOwner nonReentrant {
        require(holder != address(0), "Invalid holder");
        require(pledgeStatus[etrKey].pledgee == address(0), "Cannot redeem while pledged");
        require(!isRedeemed[etrKey], "Already redeemed");

        isRedeemed[etrKey] = true;

        emit ETRRedeemed(etrKey, holder, block.timestamp);
    }

    // ============ View Functions ============

    /**
     * @notice Check if ETR is currently pledged
     * @param etrKey The ETR identifier
     * @return True if ETR has an active pledge
     */
    function isPledged(bytes32 etrKey) external view returns (bool) {
        return pledgeStatus[etrKey].pledgee != address(0);
    }

    /**
     * @notice Get pledge details for an ETR
     * @param etrKey The ETR identifier
     * @return pledgee The bank/lender address (zero if not pledged)
     * @return timestamp When pledge was created (zero if not pledged)
     * @return agreementHash Hash of pledge agreement (zero if not pledged)
     */
    function getPledgeInfo(bytes32 etrKey)
        external
        view
        returns (address pledgee, uint256 timestamp, bytes32 agreementHash)
    {
        PledgeInfo storage info = pledgeStatus[etrKey];
        return (info.pledgee, info.timestamp, info.agreementHash);
    }

    /**
     * @notice Get contract version
     */
    function version() external pure returns (string memory) {
        return "1.0.0";
    }
}
