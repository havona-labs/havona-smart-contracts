// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

/**
 * @title HavonaAgentReputation
 * @notice ERC-8004 compliant reputation/feedback registry for Havona agents
 * @dev Stores structured feedback signals with dual-tag categorisation and
 *      on-chain aggregation. Off-chain extensibility via feedbackURI + hash.
 *
 * DESIGN:
 * - Fixed-point scoring: int128 value with configurable decimal precision (0-18)
 * - Dual tagging: tag1 (domain) + tag2 (subdomain) for filtered aggregation
 * - Off-chain detail: feedbackURI + feedbackHash for extended reports
 * - Sybil resistance: summary queries require explicit client address lists
 *
 * TAG TAXONOMY (initial):
 * - oracle_accuracy / dcsa_adapter, ais_adapter
 * - document_validation / bol_validator, loc_validator
 * - trade_execution / blotting_agent, finance_agent
 * - compliance_check / sanctions_agent, kyc_agent
 *
 * @custom:security-contact security@havona.io
 * @custom:version 1.0.0
 */
contract HavonaAgentReputation is Ownable, ReentrancyGuard {
    // ============ Storage ============

    struct Feedback {
        address client;
        int128 value;
        uint8 valueDecimals;
        bytes32 tag1;
        bytes32 tag2;
        string endpoint;
        string feedbackURI;
        bytes32 feedbackHash;
        uint256 timestamp;
        bool revoked;
    }

    /// @notice All feedback entries per agent
    mapping(uint256 agentId => Feedback[]) private _feedback;

    // ============ Events ============

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

    // ============ Constructor ============

    constructor() Ownable(msg.sender) {}

    // ============ Write Functions ============

    /**
     * @notice Submit feedback for an agent
     * @param agentId The agent being rated
     * @param client Address of the entity providing feedback
     * @param value Fixed-point score (positive or negative)
     * @param valueDecimals Decimal places for value interpretation (0-18)
     * @param tag1 Primary category tag (e.g., keccak256("oracle_accuracy"))
     * @param tag2 Secondary category tag (e.g., keccak256("dcsa_adapter"))
     * @param endpoint Service endpoint being rated
     * @param feedbackURI URI to off-chain detailed feedback report
     * @param feedbackHash KECCAK-256 hash of off-chain report for integrity
     * @return feedbackIndex Index of the new feedback entry
     */
    function giveFeedback(
        uint256 agentId,
        address client,
        int128 value,
        uint8 valueDecimals,
        bytes32 tag1,
        bytes32 tag2,
        string calldata endpoint,
        string calldata feedbackURI,
        bytes32 feedbackHash
    ) external onlyOwner nonReentrant returns (uint256) {
        require(client != address(0), "Invalid client");
        require(valueDecimals <= 18, "Decimals exceed 18");

        uint256 feedbackIndex = _feedback[agentId].length;

        _feedback[agentId].push(
            Feedback({
                client: client,
                value: value,
                valueDecimals: valueDecimals,
                tag1: tag1,
                tag2: tag2,
                endpoint: endpoint,
                feedbackURI: feedbackURI,
                feedbackHash: feedbackHash,
                timestamp: block.timestamp,
                revoked: false
            })
        );

        emit FeedbackSubmitted(agentId, client, value, valueDecimals, tag1, tag2, feedbackIndex);
        return feedbackIndex;
    }

    /**
     * @notice Revoke a specific feedback entry (marks as invalid)
     * @param agentId The agent whose feedback is being revoked
     * @param feedbackIndex Index of the feedback entry to revoke
     */
    function revokeFeedback(uint256 agentId, uint256 feedbackIndex) external onlyOwner {
        require(feedbackIndex < _feedback[agentId].length, "Index out of bounds");
        require(!_feedback[agentId][feedbackIndex].revoked, "Already revoked");

        _feedback[agentId][feedbackIndex].revoked = true;

        emit FeedbackRevoked(agentId, feedbackIndex);
    }

    // ============ View Functions ============

    /**
     * @notice Get aggregated reputation summary filtered by client addresses and tags
     * @param agentId The agent to query
     * @param clientAddresses List of trusted client addresses to include
     * @param tag1 Primary tag filter (bytes32(0) for no filter)
     * @param tag2 Secondary tag filter (bytes32(0) for no filter)
     * @return count Number of matching non-revoked feedback entries
     * @return summaryValue Sum of matching values (caller divides by count for average)
     * @return summaryDecimals Decimal precision of summaryValue
     */
    function getSummary(uint256 agentId, address[] calldata clientAddresses, bytes32 tag1, bytes32 tag2)
        external
        view
        returns (uint256 count, int256 summaryValue, uint8 summaryDecimals)
    {
        Feedback[] storage entries = _feedback[agentId];
        summaryDecimals = 0;

        for (uint256 i = 0; i < entries.length; i++) {
            Feedback storage entry = entries[i];

            if (entry.revoked) continue;
            if (tag1 != bytes32(0) && entry.tag1 != tag1) continue;
            if (tag2 != bytes32(0) && entry.tag2 != tag2) continue;

            bool clientMatch = clientAddresses.length == 0;
            for (uint256 j = 0; j < clientAddresses.length; j++) {
                if (entry.client == clientAddresses[j]) {
                    clientMatch = true;
                    break;
                }
            }
            if (!clientMatch) continue;

            count++;
            summaryValue += int256(entry.value);

            if (entry.valueDecimals > summaryDecimals) {
                summaryDecimals = entry.valueDecimals;
            }
        }
    }

    /**
     * @notice Get total number of feedback entries for an agent
     * @param agentId The agent to query
     * @return Total feedback count (including revoked)
     */
    function getFeedbackCount(uint256 agentId) external view returns (uint256) {
        return _feedback[agentId].length;
    }

    /**
     * @notice Get a specific feedback entry
     * @param agentId The agent to query
     * @param feedbackIndex Index of the feedback entry
     * @return client Feedback provider address
     * @return value Score value
     * @return valueDecimals Score decimal precision
     * @return tag1 Primary category
     * @return tag2 Secondary category
     * @return timestamp When feedback was submitted
     * @return revoked Whether feedback has been revoked
     */
    function getFeedback(uint256 agentId, uint256 feedbackIndex)
        external
        view
        returns (
            address client,
            int128 value,
            uint8 valueDecimals,
            bytes32 tag1,
            bytes32 tag2,
            uint256 timestamp,
            bool revoked
        )
    {
        require(feedbackIndex < _feedback[agentId].length, "Index out of bounds");
        Feedback storage entry = _feedback[agentId][feedbackIndex];
        return (entry.client, entry.value, entry.valueDecimals, entry.tag1, entry.tag2, entry.timestamp, entry.revoked);
    }

    /**
     * @notice Get contract version
     */
    function version() external pure returns (string memory) {
        return "1.0.0";
    }
}
