// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/**
 * @title IP256Verifier
 * @notice Interface for P-256 (secp256r1) ECDSA signature verification
 * @dev Standard interface from daimo-eth/p256-verifier
 *
 * This interface allows verification of signatures made by hardware security
 * devices (YubiKey, Secure Enclave, TPM) that use the NIST P-256 curve.
 *
 * Reference: https://github.com/daimo-eth/p256-verifier
 * Deterministic address: 0xc2b78104907F722DABAc4C69f826a522B2754DE4
 */
interface IP256Verifier {
    /**
     * @notice Verifies a P-256 (secp256r1) ECDSA signature
     * @param messageHash The hash of the message that was signed (SHA-256)
     * @param r The r component of the ECDSA signature (32 bytes)
     * @param s The s component of the ECDSA signature (32 bytes)
     * @param x The x coordinate of the public key (32 bytes)
     * @param y The y coordinate of the public key (32 bytes)
     * @return valid True if the signature is valid, false otherwise
     */
    function verify(bytes32 messageHash, uint256 r, uint256 s, uint256 x, uint256 y)
        external
        view
        returns (bool valid);
}
