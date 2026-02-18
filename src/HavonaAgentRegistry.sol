// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC721/extensions/ERC721URIStorage.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/cryptography/EIP712.sol";
import "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";

/**
 * @title HavonaAgentRegistry
 * @notice ERC-8004 compliant agent identity registry for Havona RWA platform
 * @dev Each agent is represented as an ERC-721 token whose URI points to a
 *      structured JSON metadata file (ERC-8004 registration file format).
 *
 * DESIGN:
 * - NFT ownership = organisational control (Havona server address)
 * - Agent wallet = operational key pair (separate from NFT owner)
 * - EIP-712 signatures verify wallet change requests
 * - All write operations restricted to contract owner (centralised Phase 1)
 *
 * ERC-8004 ALIGNMENT:
 * - register()       -> Identity Registry register()
 * - setAgentURI()    -> Identity Registry setAgentURI()
 * - setAgentWallet() -> Identity Registry setAgentWallet() with EIP-712
 * - tokenURI()       -> Standard ERC-721 metadata resolution
 *
 * @custom:security-contact security@havona.io
 * @custom:version 1.0.0
 */
contract HavonaAgentRegistry is ERC721URIStorage, Ownable, EIP712 {
    using ECDSA for bytes32;

    // ============ Storage ============

    /// @notice Auto-incrementing agent ID counter (starts at 1)
    uint256 private _nextAgentId;

    /// @notice Operational wallet for each agent (distinct from NFT owner)
    mapping(uint256 agentId => address) private _agentWallets;

    /// @notice Active/inactive status for each agent
    mapping(uint256 agentId => bool) private _isActive;

    /// @notice Used nonces for EIP-712 replay protection
    mapping(address wallet => uint256) private _nonces;

    // ============ EIP-712 Type Hash ============

    bytes32 public constant SET_WALLET_TYPEHASH =
        keccak256("SetAgentWallet(uint256 agentId,address newWallet,uint256 nonce,uint256 deadline)");

    // ============ Events ============

    event AgentRegistered(uint256 indexed agentId, address indexed wallet, string agentURI);
    event AgentWalletUpdated(uint256 indexed agentId, address indexed oldWallet, address indexed newWallet);
    event AgentDeactivated(uint256 indexed agentId);
    event AgentReactivated(uint256 indexed agentId);

    // ============ Constructor ============

    constructor() ERC721("HavonaAgent", "HAGENT") Ownable(msg.sender) EIP712("HavonaAgentRegistry", "1") {
        _nextAgentId = 1;
    }

    // ============ Write Functions ============

    /**
     * @notice Register a new agent identity
     * @param agentURI Metadata URI (ERC-8004 registration file)
     * @param wallet Operational wallet address for this agent
     * @return agentId The newly minted agent ID
     */
    function register(string calldata agentURI, address wallet) external onlyOwner returns (uint256) {
        require(wallet != address(0), "Invalid wallet");
        require(bytes(agentURI).length > 0, "Empty URI");

        uint256 agentId = _nextAgentId++;

        _mint(msg.sender, agentId);
        _setTokenURI(agentId, agentURI);
        _agentWallets[agentId] = wallet;
        _isActive[agentId] = true;

        emit AgentRegistered(agentId, wallet, agentURI);
        return agentId;
    }

    /**
     * @notice Update agent metadata URI
     * @param agentId The agent to update
     * @param newURI New metadata URI
     */
    function setAgentURI(uint256 agentId, string calldata newURI) external onlyOwner {
        _requireOwned(agentId);
        require(bytes(newURI).length > 0, "Empty URI");
        _setTokenURI(agentId, newURI);
    }

    /**
     * @notice Update agent operational wallet with EIP-712 signature
     * @param agentId The agent to update
     * @param newWallet New operational wallet address
     * @param deadline Signature expiry timestamp
     * @param signature EIP-712 signature from the CURRENT wallet authorising the change
     */
    function setAgentWallet(uint256 agentId, address newWallet, uint256 deadline, bytes calldata signature)
        external
        onlyOwner
    {
        _requireOwned(agentId);
        require(newWallet != address(0), "Invalid wallet");
        require(block.timestamp <= deadline, "Signature expired");

        address currentWallet = _agentWallets[agentId];
        require(currentWallet != address(0), "No wallet set");

        uint256 nonce = _nonces[currentWallet]++;

        bytes32 structHash = keccak256(abi.encode(SET_WALLET_TYPEHASH, agentId, newWallet, nonce, deadline));
        bytes32 digest = _hashTypedDataV4(structHash);
        address signer = digest.recover(signature);
        require(signer == currentWallet, "Invalid signature");

        _agentWallets[agentId] = newWallet;

        emit AgentWalletUpdated(agentId, currentWallet, newWallet);
    }

    /**
     * @notice Deactivate an agent (soft disable, NFT retained)
     * @param agentId The agent to deactivate
     */
    function deactivate(uint256 agentId) external onlyOwner {
        _requireOwned(agentId);
        require(_isActive[agentId], "Already inactive");
        _isActive[agentId] = false;
        emit AgentDeactivated(agentId);
    }

    /**
     * @notice Reactivate a previously deactivated agent
     * @param agentId The agent to reactivate
     */
    function reactivate(uint256 agentId) external onlyOwner {
        _requireOwned(agentId);
        require(!_isActive[agentId], "Already active");
        _isActive[agentId] = true;
        emit AgentReactivated(agentId);
    }

    // ============ View Functions ============

    /**
     * @notice Get the operational wallet for an agent
     * @param agentId The agent to query
     * @return The agent's operational wallet address
     */
    function getAgentWallet(uint256 agentId) external view returns (address) {
        _requireOwned(agentId);
        return _agentWallets[agentId];
    }

    /**
     * @notice Check if an agent is currently active
     * @param agentId The agent to query
     * @return True if agent is active
     */
    function isActive(uint256 agentId) external view returns (bool) {
        _requireOwned(agentId);
        return _isActive[agentId];
    }

    /**
     * @notice Get the total number of registered agents
     * @return The next agent ID minus 1 (total minted)
     */
    function totalAgents() external view returns (uint256) {
        return _nextAgentId - 1;
    }

    /**
     * @notice Get the current nonce for a wallet (for EIP-712 signature construction)
     * @param wallet The wallet address to query
     * @return Current nonce value
     */
    function nonces(address wallet) external view returns (uint256) {
        return _nonces[wallet];
    }

    /**
     * @notice Get contract version
     */
    function version() external pure returns (string memory) {
        return "1.0.0";
    }

    // ============ Required Overrides ============

    function supportsInterface(bytes4 interfaceId) public view override(ERC721URIStorage) returns (bool) {
        return super.supportsInterface(interfaceId);
    }

    function tokenURI(uint256 tokenId) public view override(ERC721URIStorage) returns (string memory) {
        return super.tokenURI(tokenId);
    }
}
