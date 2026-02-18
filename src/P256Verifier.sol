// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "./interfaces/IP256Verifier.sol";

/**
 * @title P256Verifier
 * @notice P-256 (secp256r1) ECDSA signature verification for YubiKey/WebAuthn
 * @dev This implementation uses pre-compiled modular exponentiation for efficiency.
 *
 * For production, consider:
 * 1. Using RIP-7212 precompile when available (0x100 address, ~3450 gas)
 * 2. Using daimo-eth/p256-verifier (0xc2b78104907F722DABAc4C69f826a522B2754DE4)
 *
 * This implementation is based on the EllipticCurve library approach using
 * modular arithmetic with the modexp precompile (0x05).
 *
 * Gas cost: ~300,000-400,000 (contract-based verification is expensive)
 *
 * @custom:security-contact security@havona.io
 */
contract P256Verifier is IP256Verifier {
    // P-256 curve parameters
    // p = 2^256 - 2^224 + 2^192 + 2^96 - 1 (field prime)
    uint256 constant P = 0xFFFFFFFF00000001000000000000000000000000FFFFFFFFFFFFFFFFFFFFFFFF;

    // n = curve order
    uint256 constant N = 0xFFFFFFFF00000000FFFFFFFFFFFFFFFFBCE6FAADA7179E84F3B9CAC2FC632551;

    // a = -3 mod p (curve parameter)
    uint256 constant A = 0xFFFFFFFF00000001000000000000000000000000FFFFFFFFFFFFFFFFFFFFFFFC;

    // b = curve parameter
    uint256 constant B = 0x5AC635D8AA3A93E7B3EBBD55769886BC651D06B0CC53B0F63BCE3C3E27D2604B;

    // Generator point coordinates
    uint256 constant GX = 0x6B17D1F2E12C4247F8BCE6E563A440F277037D812DEB33A0F4A13945D898C296;
    uint256 constant GY = 0x4FE342E2FE1A7F9B8EE7EB4A7C0F9E162BCE33576B315ECECBB6406837BF51F5;

    // For testing: skip actual verification (set to true for local development)
    bool public immutable skipVerification;

    /**
     * @notice Constructor
     * @param _skipVerification Set to true for testing (always returns true)
     */
    constructor(bool _skipVerification) {
        skipVerification = _skipVerification;
    }

    /**
     * @notice Verify a P-256 ECDSA signature
     * @param messageHash The SHA-256 hash of the message
     * @param r The r component of the signature
     * @param s The s component of the signature
     * @param x The x coordinate of the public key
     * @param y The y coordinate of the public key
     * @return valid True if the signature is valid
     */
    function verify(bytes32 messageHash, uint256 r, uint256 s, uint256 x, uint256 y)
        external
        view
        override
        returns (bool valid)
    {
        // Input validation
        if (r == 0 || r >= N) return false;
        if (s == 0 || s >= N) return false;
        if (x >= P || y >= P) return false;

        // Check that the public key is on the curve: y^2 = x^3 + ax + b (mod p)
        if (!isOnCurve(x, y)) return false;

        // For testing mode, skip actual cryptographic verification
        if (skipVerification) {
            return true;
        }

        // Perform full ECDSA verification
        return _verifyECDSA(uint256(messageHash), r, s, x, y);
    }

    /**
     * @notice Check if a point is on the P-256 curve
     * @param x X coordinate
     * @param y Y coordinate
     * @return True if point is on curve
     */
    function isOnCurve(uint256 x, uint256 y) public pure returns (bool) {
        if (x == 0 && y == 0) return false; // Point at infinity not valid for public key

        // y^2 mod p
        uint256 lhs = mulmod(y, y, P);

        // x^3 + ax + b mod p
        uint256 rhs = addmod(addmod(mulmod(mulmod(x, x, P), x, P), mulmod(A, x, P), P), B, P);

        return lhs == rhs;
    }

    /**
     * @notice Internal ECDSA verification using scalar multiplication
     */
    function _verifyECDSA(uint256 e, uint256 r, uint256 s, uint256 qx, uint256 qy) internal view returns (bool) {
        // Compute s^-1 mod n
        uint256 sInv = _modInverse(s, N);
        if (sInv == 0) return false;

        // u1 = e * s^-1 mod n
        uint256 u1 = mulmod(e, sInv, N);

        // u2 = r * s^-1 mod n
        uint256 u2 = mulmod(r, sInv, N);

        // Compute point R = u1*G + u2*Q
        // First compute u1*G
        (uint256 x1, uint256 y1) = _scalarMult(GX, GY, u1);

        // Then compute u2*Q
        (uint256 x2, uint256 y2) = _scalarMult(qx, qy, u2);

        // Add the points
        (uint256 rx,) = _addPoints(x1, y1, x2, y2);

        // Check if x coordinate of R equals r mod n
        return (rx % N) == r;
    }

    /**
     * @notice Modular inverse using Fermat's little theorem: a^(-1) = a^(n-2) mod n
     */
    function _modInverse(uint256 a, uint256 modulus) internal view returns (uint256) {
        return _modExp(a, modulus - 2, modulus);
    }

    /**
     * @notice Modular exponentiation using the precompile at 0x05
     */
    function _modExp(uint256 base, uint256 exp, uint256 modulus) internal view returns (uint256 result) {
        bytes memory input = abi.encodePacked(
            uint256(32), // base length
            uint256(32), // exponent length
            uint256(32), // modulus length
            base,
            exp,
            modulus
        );

        assembly {
            let success := staticcall(gas(), 0x05, add(input, 0x20), mload(input), 0x00, 0x20)
            if iszero(success) { revert(0, 0) }
            result := mload(0x00)
        }
    }

    /**
     * @notice Scalar multiplication: k * P using double-and-add
     */
    function _scalarMult(uint256 px, uint256 py, uint256 k) internal view returns (uint256, uint256) {
        uint256 rx;
        uint256 ry;
        bool isInfinity = true;

        uint256 qx = px;
        uint256 qy = py;

        while (k > 0) {
            if (k & 1 == 1) {
                if (isInfinity) {
                    rx = qx;
                    ry = qy;
                    isInfinity = false;
                } else {
                    (rx, ry) = _addPoints(rx, ry, qx, qy);
                }
            }
            (qx, qy) = _doublePoint(qx, qy);
            k >>= 1;
        }

        return (rx, ry);
    }

    /**
     * @notice Point addition: P + Q
     */
    function _addPoints(uint256 x1, uint256 y1, uint256 x2, uint256 y2)
        internal
        view
        returns (uint256 x3, uint256 y3)
    {
        if (x1 == x2 && y1 == y2) {
            return _doublePoint(x1, y1);
        }

        // lambda = (y2 - y1) / (x2 - x1) mod p
        uint256 dy = addmod(y2, P - y1, P);
        uint256 dx = addmod(x2, P - x1, P);
        uint256 lambda = mulmod(dy, _modInverse(dx, P), P);

        // x3 = lambda^2 - x1 - x2 mod p
        x3 = addmod(mulmod(lambda, lambda, P), P - addmod(x1, x2, P), P);

        // y3 = lambda * (x1 - x3) - y1 mod p
        y3 = addmod(mulmod(lambda, addmod(x1, P - x3, P), P), P - y1, P);
    }

    /**
     * @notice Point doubling: 2 * P
     */
    function _doublePoint(uint256 x, uint256 y) internal view returns (uint256 x3, uint256 y3) {
        // lambda = (3 * x^2 + a) / (2 * y) mod p
        uint256 numerator = addmod(mulmod(3, mulmod(x, x, P), P), A, P);
        uint256 denominator = mulmod(2, y, P);
        uint256 lambda = mulmod(numerator, _modInverse(denominator, P), P);

        // x3 = lambda^2 - 2 * x mod p
        x3 = addmod(mulmod(lambda, lambda, P), P - mulmod(2, x, P), P);

        // y3 = lambda * (x - x3) - y mod p
        y3 = addmod(mulmod(lambda, addmod(x, P - x3, P), P), P - y, P);
    }
}
