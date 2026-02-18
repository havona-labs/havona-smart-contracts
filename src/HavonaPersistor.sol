// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "./CBORDecoding.sol";
import "./interfaces/IP256Verifier.sol";
import "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import "@openzeppelin/contracts/utils/cryptography/EIP712.sol";
import "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

/**
 * @title HavonaPersistor
 * @notice Secure CBOR data storage for Havona trade records
 * @dev Designed for confidential EVM deployment (TEE-based chains). Contract
 *      storage is encrypted at the hardware level when deployed on a TEE chain;
 *      per-key access control (`canAccess`) governs who can read each record.
 *
 * KEY PRINCIPLES:
 * - Data is private by default on confidential EVM (TEE encryption)
 * - Only authorized accounts can read data (per-key access control)
 * - Havona admin controls who can access what
 * - No application logic in contract (lives in Havona server/DGraph)
 *
 * @custom:security-contact security@havona.io
 * @custom:version 1.1.0
 */
contract HavonaPersistor is EIP712, Ownable, ReentrancyGuard {
    using CBORDecoding for bytes;
    using ECDSA for bytes32;
    using EnumerableSet for EnumerableSet.Bytes32Set;

    // ============ Storage ============

    /// @notice CBOR blob storage
    mapping(bytes32 => bytes) private dataBlobs;

    /// @notice All keys for enumeration
    EnumerableSet.Bytes32Set private allKeys;

    /// @notice Version history (auto-archive on update)
    mapping(bytes32 => uint256) private blobVersions;

    /// @notice Access control: key => account => allowed
    /// @dev Controls per-key read access; on TEE chains this governs decryption
    mapping(bytes32 => mapping(address => bool)) public canAccess;

    /// @notice Content hashes for verification
    mapping(bytes32 => bytes32) public contentHashes;

    /// @notice Nonces for signed operations
    mapping(address => uint256) public nonces;

    /// @notice Used signatures (prevent replay)
    mapping(bytes32 => bool) private usedSignatures;

    /// @notice P256 Verifier contract for YubiKey/WebAuthn signature verification
    IP256Verifier public p256Verifier;

    // ============ Constants ============

    bytes32 private constant BLOB_TYPEHASH = keccak256("Blob(bytes32 key,bytes data,uint256 nonce,uint256 expiry)");

    uint256 public constant MAX_VERSIONS_PER_KEY = 100;
    uint256 public constant MAX_BATCH_SIZE = 50;

    // ============ Events ============
    // Note: On TEE chains, event logs are only visible to authorized accounts

    event BlobStored(
        bytes32 indexed key, address indexed actor, uint256 dataLength, uint256 timestamp, bytes32 contentHash
    );

    event BlobRemoved(bytes32 indexed key, address indexed actor, uint256 timestamp);

    event BlobVersioned(bytes32 indexed key, uint256 version, uint256 timestamp, bytes32 oldHash, bytes32 newHash);

    event AccessGranted(bytes32 indexed key, address indexed account, uint256 timestamp);

    event AccessRevoked(bytes32 indexed key, address indexed account, uint256 timestamp);

    event BlobStoredP256(
        bytes32 indexed key,
        uint256 publicKeyX,
        uint256 publicKeyY,
        uint256 dataLength,
        uint256 timestamp,
        bytes32 contentHash
    );

    event P256VerifierUpdated(address indexed oldVerifier, address indexed newVerifier);

    // ============ Constructor ============

    constructor() EIP712("HavonaPersistor", "1") Ownable(msg.sender) {}

    // ============ Core Storage Functions ============

    /**
     * @notice Store CBOR-encoded blob (owner only)
     * @param key Unique identifier
     * @param cborData CBOR-encoded data
     * @dev Only owner can write. Data is encrypted in TEE on confidential EVM chains.
     */
    function setBlob(bytes32 key, bytes calldata cborData) external onlyOwner nonReentrant {
        _setBlob(key, cborData, msg.sender);
    }

    /**
     * @notice Store signed blob with EIP-712 verification
     * @param key Unique identifier
     * @param cborData CBOR-encoded data
     * @param signature EIP-712 signature
     * @param signer Expected signer
     * @param expiry Signature expiration
     * @dev Owner submits on behalf of user after signature verification
     */
    function setSignedBlob(
        bytes32 key,
        bytes calldata cborData,
        bytes calldata signature,
        address signer,
        uint256 expiry
    ) external onlyOwner nonReentrant {
        require(block.timestamp <= expiry, "Signature expired");
        require(expiry <= block.timestamp + 1 hours, "Expiry too far");

        // Build EIP-712 hash
        uint256 signerNonce = nonces[signer];
        bytes32 structHash = keccak256(abi.encode(BLOB_TYPEHASH, key, keccak256(cborData), signerNonce, expiry));
        bytes32 hash = _hashTypedDataV4(structHash);

        // Verify signature
        address recoveredSigner = hash.recover(signature);
        require(recoveredSigner == signer, "Invalid signature");

        // Prevent replay
        bytes32 signatureHash = keccak256(signature);
        require(!usedSignatures[signatureHash], "Signature already used");
        usedSignatures[signatureHash] = true;
        nonces[signer]++;

        _setBlob(key, cborData, signer);
    }

    /**
     * @notice Store blob with P-256 signature verification (YubiKey/WebAuthn)
     * @param key Unique identifier
     * @param cborData CBOR-encoded data
     * @param r Signature r component (32 bytes)
     * @param s Signature s component (32 bytes)
     * @param x Public key x coordinate (32 bytes)
     * @param y Public key y coordinate (32 bytes)
     * @dev Owner submits after collecting YubiKey signature from user
     *
     * Security: The P256Verifier contract verifies that the signature
     * was created by the private key corresponding to (x, y) over the
     * keccak256 hash of the CBOR data. This proves the YubiKey holder
     * authorized this specific data.
     *
     * Gas cost: ~300,000-400,000 (P256 verification is expensive)
     */
    function setSignedBlobP256(bytes32 key, bytes calldata cborData, uint256 r, uint256 s, uint256 x, uint256 y)
        external
        onlyOwner
        nonReentrant
    {
        require(address(p256Verifier) != address(0), "P256 verifier not set");

        // Compute hash of the data (this is what the YubiKey signed)
        bytes32 messageHash = keccak256(cborData);

        // Verify P-256 signature on-chain
        bool valid = p256Verifier.verify(messageHash, r, s, x, y);
        require(valid, "Invalid P256 signature");

        // Store the data with content hash
        bytes32 contentHash = messageHash;
        dataBlobs[key] = cborData;
        allKeys.add(key);
        contentHashes[key] = contentHash;

        emit BlobStoredP256(key, x, y, cborData.length, block.timestamp, contentHash);
    }

    /**
     * @notice Store data with P-256 WebAuthn signature verification
     * @dev WebAuthn signatures sign: authenticatorData || SHA256(clientDataJSON)
     *      This function accepts the pre-computed signed message hash for verification.
     * @param key Unique identifier
     * @param cborData CBOR encoded data to store
     * @param signedMessageHash Pre-computed hash that was signed (authenticatorData || SHA256(clientDataJSON))
     * @param r ECDSA r component (256-bit integer)
     * @param s ECDSA s component (256-bit integer)
     * @param x P-256 public key X coordinate
     * @param y P-256 public key Y coordinate
     */
    function setSignedBlobP256WebAuthn(
        bytes32 key,
        bytes calldata cborData,
        bytes32 signedMessageHash,
        uint256 r,
        uint256 s,
        uint256 x,
        uint256 y
    ) external onlyOwner nonReentrant {
        require(address(p256Verifier) != address(0), "P256 verifier not set");

        // Verify P-256 signature against the WebAuthn signed message
        bool valid = p256Verifier.verify(signedMessageHash, r, s, x, y);
        require(valid, "Invalid P256 signature");

        // Store the data with content hash
        bytes32 contentHash = keccak256(cborData);
        dataBlobs[key] = cborData;
        allKeys.add(key);
        contentHashes[key] = contentHash;

        emit BlobStoredP256(key, x, y, cborData.length, block.timestamp, contentHash);
    }

    /**
     * @notice Set the P256 verifier contract address
     * @param _verifier Address of the P256Verifier contract
     */
    function setP256Verifier(address _verifier) external onlyOwner {
        require(_verifier != address(0), "Invalid verifier address");
        address oldVerifier = address(p256Verifier);
        p256Verifier = IP256Verifier(_verifier);
        emit P256VerifierUpdated(oldVerifier, _verifier);
    }

    /**
     * @notice Batch store (gas optimization)
     * @param keys Array of identifiers
     * @param cborData Array of CBOR data
     */
    function setBlobsBatch(bytes32[] calldata keys, bytes[] calldata cborData) external onlyOwner nonReentrant {
        require(keys.length == cborData.length, "Length mismatch");
        require(keys.length <= MAX_BATCH_SIZE, "Batch too large");

        for (uint256 i = 0; i < keys.length; i++) {
            _setBlob(keys[i], cborData[i], msg.sender);
        }
    }

    /**
     * @notice Internal storage with versioning
     */
    function _setBlob(bytes32 key, bytes calldata cborData, address actor) private {
        bytes32 oldHash = contentHashes[key];
        bytes32 newHash = keccak256(cborData);

        // Auto-version existing data
        if (dataBlobs[key].length > 0) {
            uint256 currentVersion = blobVersions[key] + 1;
            require(currentVersion <= MAX_VERSIONS_PER_KEY, "Max versions reached");

            bytes32 versionKey = _makeVersionKey(key, currentVersion);
            dataBlobs[versionKey] = dataBlobs[key];
            blobVersions[key] = currentVersion;

            emit BlobVersioned(key, currentVersion, block.timestamp, oldHash, newHash);
        }

        // Store new data
        dataBlobs[key] = cborData;
        allKeys.add(key);
        contentHashes[key] = newHash;

        emit BlobStored(key, actor, cborData.length, block.timestamp, newHash);
    }

    /**
     * @notice Remove blob (owner only)
     * @param key Blob identifier
     */
    function removeBlob(bytes32 key) external onlyOwner nonReentrant {
        require(dataBlobs[key].length > 0, "Blob does not exist");

        delete dataBlobs[key];
        delete contentHashes[key];
        allKeys.remove(key);

        emit BlobRemoved(key, msg.sender, block.timestamp);
    }

    // ============ Access Control ============

    /**
     * @notice Grant read access to account for specific key
     * @param key Blob identifier
     * @param account Address to grant access
     * @dev Grants read access to this key; on TEE chains enables decryption for the account
     */
    function grantAccess(bytes32 key, address account) external onlyOwner {
        canAccess[key][account] = true;
        emit AccessGranted(key, account, block.timestamp);
    }

    /**
     * @notice Grant batch access (gas optimization)
     */
    function grantAccessBatch(bytes32[] calldata keys, address[] calldata accounts) external onlyOwner {
        require(keys.length == accounts.length, "Length mismatch");
        for (uint256 i = 0; i < keys.length; i++) {
            canAccess[keys[i]][accounts[i]] = true;
            emit AccessGranted(keys[i], accounts[i], block.timestamp);
        }
    }

    /**
     * @notice Revoke access
     */
    function revokeAccess(bytes32 key, address account) external onlyOwner {
        canAccess[key][account] = false;
        emit AccessRevoked(key, account, block.timestamp);
    }

    // ============ Retrieval Functions ============

    /**
     * @notice Get blob data
     * @dev Only owner and authorized accounts can read; TEE chains enforce encryption
     */
    function getBlob(bytes32 key) external view returns (bytes memory) {
        require(_hasAccess(msg.sender, key), "Access denied");
        return dataBlobs[key];
    }

    /**
     * @notice Get blob version
     */
    function getBlobVersion(bytes32 key, uint256 versionNumber) external view returns (bytes memory) {
        require(_hasAccess(msg.sender, key), "Access denied");
        require(versionNumber > 0 && versionNumber <= blobVersions[key], "Invalid version");

        bytes32 versionKey = _makeVersionKey(key, versionNumber);
        return dataBlobs[versionKey];
    }

    /**
     * @notice Check if blob exists
     */
    function hasBlob(bytes32 key) external view returns (bool) {
        return dataBlobs[key].length > 0;
    }

    /**
     * @notice Get blob count
     */
    function getBlobCount() external view returns (uint256) {
        return allKeys.length();
    }

    /**
     * @notice Get key by index
     */
    function getKeyAtIndex(uint256 index) external view returns (bytes32) {
        require(index < allKeys.length(), "Index out of bounds");
        return allKeys.at(index);
    }

    /**
     * @notice Get all keys (WARNING: expensive for large sets)
     */
    function getAllKeys() external view returns (bytes32[] memory) {
        uint256 length = allKeys.length();
        bytes32[] memory keys = new bytes32[](length);
        for (uint256 i = 0; i < length; i++) {
            keys[i] = allKeys.at(i);
        }
        return keys;
    }

    /**
     * @notice Get paginated blobs (gas-efficient)
     * @dev Only returns data the caller has access to
     */
    function getBlobsPaginated(uint256 offset, uint256 limit)
        external
        view
        returns (bytes32[] memory keys, bytes[] memory values, uint256 total)
    {
        total = allKeys.length();
        uint256 end = offset + limit;
        if (end > total) end = total;

        uint256 actualLength = end > offset ? end - offset : 0;
        keys = new bytes32[](actualLength);
        values = new bytes[](actualLength);

        for (uint256 i = 0; i < actualLength; i++) {
            bytes32 key = allKeys.at(offset + i);
            keys[i] = key;

            // Only return data if caller has access
            if (_hasAccess(msg.sender, key)) {
                values[i] = dataBlobs[key];
            }
        }
    }

    /**
     * @notice Get version count
     */
    function getBlobVersionCount(bytes32 key) external view returns (uint256) {
        return blobVersions[key];
    }

    // ============ CBOR Decoding ============

    /**
     * @notice Decode CBOR map
     */
    function decodeMapping(bytes32 key) external view returns (bytes[] memory keys, bytes[] memory values) {
        require(_hasAccess(msg.sender, key), "Access denied");
        require(dataBlobs[key].length > 0, "Blob does not exist");

        bytes[2][] memory kvPairs = dataBlobs[key].decodeMapping();
        uint256 len = kvPairs.length;
        keys = new bytes[](len);
        values = new bytes[](len);

        for (uint256 i = 0; i < len; i++) {
            keys[i] = kvPairs[i][0];
            values[i] = kvPairs[i][1];
        }
    }

    /**
     * @notice Decode array item
     */
    function decodeArrayItem(bytes32 key, uint256 index) external view returns (bytes memory) {
        require(_hasAccess(msg.sender, key), "Access denied");
        require(dataBlobs[key].length > 0, "Blob does not exist");
        require(index <= type(uint64).max, "Index too large");

        return dataBlobs[key].decodeArrayGetItem(uint64(index));
    }

    // ============ Utility Functions ============

    /**
     * @notice Check if account has access to key
     */
    function hasAccess(address account, bytes32 key) external view returns (bool) {
        return _hasAccess(account, key);
    }

    /**
     * @notice Verify content hash
     */
    function verifyContentHash(bytes32 key, bytes calldata data) external view returns (bool) {
        return contentHashes[key] == keccak256(data);
    }

    /**
     * @notice Get domain separator for EIP-712
     */
    function domainSeparatorV4() external view returns (bytes32) {
        return _domainSeparatorV4();
    }

    /**
     * @notice Get contract version
     */
    function version() external pure returns (string memory) {
        return "1.0.0-simple";
    }

    // ============ Internal Functions ============

    /**
     * @notice Internal access check
     * @dev Owner always has access. Authorized accounts can read their granted keys.
     */
    function _hasAccess(address account, bytes32 key) private view returns (bool) {
        // Owner (Havona admin) always has access
        if (account == owner()) return true;

        // Check explicit permission
        return canAccess[key][account];
    }

    /**
     * @notice Generate version key
     */
    function _makeVersionKey(bytes32 key, uint256 versionNumber) private pure returns (bytes32) {
        return keccak256(abi.encodePacked(key, versionNumber));
    }
}
