# Havona Smart Contracts

Solidity contracts powering the Havona trade finance platform. Built for **confidential EVM** deployment — chains backed by hardware TEEs (Intel SGX) where contract storage is encrypted at the hardware level. Trade data, counterparty identities, and pricing terms are private by default.

Compatible with [Oasis Sapphire](https://docs.oasis.io/dapp/sapphire/) and [TEN Network](https://ten.xyz), and any EVM-compatible confidential compute chain.

## Live Deployment

| Network | Contract | Address |
|---------|----------|---------|
| Sapphire Testnet (23295) | `HavonaPersistor` | [`0xb6d9e6dC...8613`](https://explorer.oasis.io/testnet/sapphire/address/0xb6d9e6dC3f13413656b74951776f1EE067758613) |
| Sapphire Testnet (23295) | `P256Verifier` | [`0x246f91EA...dD26`](https://explorer.oasis.io/testnet/sapphire/address/0x246f91EA2A6a23f4a17123b72e80718cCB7dDD26) |

Full deployment metadata: [`deployments/sapphire-testnet.json`](deployments/sapphire-testnet.json)

Mainnet deployment planned following audit. Deploy tooling supports Sapphire testnet, Sapphire mainnet, TEN Network, and local Anvil.

---

## Contracts

### `HavonaPersistor.sol`

Core persistence layer. Stores CBOR-encoded trade documents and contracts as opaque blobs with per-key access control. On confidential EVM chains the TEE ensures data is encrypted at rest; only authorised accounts can read.

**Key features:**
- EIP-712 signed writes (hardware wallet / YubiKey / WebAuthn via P256)
- Per-key access control (`canAccess[key][account]`)
- Version history — overwrites auto-archive previous content
- Nonce tracking + used-signature map (replay prevention)
- Batch read/write (`getBlobsPaginated`, `setBlobBatch`) — up to 50 ops
- OpenZeppelin `Ownable`, `ReentrancyGuard`

**Cost:** ~$0.002 per trade record at current ROSE prices on Sapphire.

---

### `ETRRegistry.sol`

Electronic Transferable Record lifecycle events, MLETR-compliant. Companion to `HavonaPersistor` — content lives in the Persistor, business events live here.

Implements the functional equivalent of possession (MLETR Article 10):

| Event | Description |
|-------|-------------|
| `ETRCreated` | Initial issuance |
| `ETRTransferred` | Change of control |
| `ETRPledged` | Pledge to financier |
| `ETRLiquidated` | Enforcement by pledgee |
| `ETRRedeemed` | Final redemption |

Compliant with UNCITRAL MLETR and the UK Electronic Trade Documents Act 2023. Events are indexed for external auditors, banks, and customs authorities.

---

### `HavonaAgentRegistry.sol` — ERC-8004

On-chain agent identity registry implementing [ERC-8004](https://github.com/ethereum/EIPs/issues/8004). Each agent is an ERC-721 token whose URI points to a structured JSON registration file.

- NFT ownership = organisational control (Havona server)
- Agent wallet = operational keypair (separate from token owner)
- EIP-712 signatures verify wallet rotation requests

**Agent types currently registered:**
- `blotting` — trade data extraction and normalisation
- `compliance_manager` — sanctions/KYC screening
- `etr_extraction` — document digitisation (BoL, CoO, Commercial Invoice)

---

### `HavonaAgentReputation.sol` — ERC-8004

Reputation and feedback registry for agents. Fixed-point scoring with dual-tag taxonomy for filtered aggregation. Off-chain detail via `feedbackURI` + hash.

**Tag taxonomy:**
```
oracle_accuracy      / dcsa_adapter, ais_adapter
document_validation  / bol_validator, loc_validator
trade_execution      / blotting_agent, finance_agent
compliance_check     / sanctions_agent, kyc_agent
```

---

### `HavonaMemberManager.sol`

On-chain member registration. Mirrors the Havona identity registry — members registered here are verifiable cross-chain.

---

### `P256Verifier.sol`

EIP-7212 compatible P-256 (secp256r1) signature verifier. Enables YubiKey and WebAuthn (passkey) hardware signatures for trade document signing without requiring software key management.

---

## Architecture

```
┌─────────────────────────────────────────────────────┐
│           Confidential EVM (TEE-encrypted)          │
│                                                     │
│   HavonaPersistor        ETRRegistry                │
│   ┌─────────────┐        ┌──────────────┐           │
│   │ CBOR blobs  │        │ Lifecycle    │           │
│   │ per-key ACL │        │ events       │           │
│   │ EIP-712 sig │        │ MLETR art.10 │           │
│   └─────────────┘        └──────────────┘           │
│                                                     │
│   HavonaAgentRegistry    HavonaAgentReputation      │
│   ┌─────────────┐        ┌──────────────┐           │
│   │ ERC-8004    │        │ ERC-8004     │           │
│   │ ERC-721     │        │ scoring      │           │
│   │ EIP-712     │        │ dual-tag     │           │
│   └─────────────┘        └──────────────┘           │
└─────────────────────────────────────────────────────┘
          ▲
          │ writes (DGraph first → blockchain second)
          │
    Havona Platform API
```

All blockchain writes flow through the Havona server. The server persists to DGraph first (source of truth for queries), then writes to the confidential EVM chain (immutable proof). Reads always come from DGraph.

---

## Deploy

### Prerequisites

```bash
# Install Foundry
curl -L https://foundry.paradigm.xyz | bash
foundryup
```

### Oasis Sapphire

```bash
# Testnet (get ROSE: https://faucet.testnet.oasis.io/)
./deploy/deploy_sapphire.sh --private-key 0xYOUR_KEY

# Mainnet
./deploy/deploy_sapphire.sh --private-key 0xYOUR_KEY --mainnet

# Dry run (build only)
./deploy/deploy_sapphire.sh --dry-run
```

### Local (Anvil)

```bash
# Start Anvil in a separate terminal
anvil

# Deploy (uses default Anvil account)
forge script script/DeployPersistor.s.sol:DeployPersistor \
  --rpc-url http://localhost:8545 \
  --broadcast
```

`deploy_sapphire.sh` verifies chain connectivity, checks your balance, runs `forge script` atomically, and saves deployment addresses to `deployments/`.

---

## Build & Test

```bash
# Build
forge build

# Run all tests
forge test -vvv

# Run specific contract tests
forge test --match-contract HavonaPersistorTest -vvv

# Gas snapshot
forge snapshot
```

**Test coverage:**

| Contract | Test file |
|----------|-----------|
| `HavonaPersistor` | `test/HavonaPersistor.t.sol` |
| `HavonaAgentRegistry` | `test/HavonaAgentRegistry.t.sol` |
| `ETRRegistry` | `test/ETRRegistry.t.sol` |
| `HavonaMemberManager` | `test/HavonaMemberManager.t.sol` |

---

## Why Confidential EVM

Standard EVM chains expose all on-chain data publicly. For trade finance this is a deal-breaker — counterparties won't publish pricing, cargo details, or contract terms on a transparent ledger.

Confidential EVM chains such as [Oasis Sapphire](https://docs.oasis.io/dapp/sapphire/) and [TEN Network](https://ten.xyz) run smart contracts inside hardware TEEs. The EVM state is encrypted; validator nodes process transactions without seeing plaintext data.

Key properties:

- **Private by default** — contract storage is encrypted at the hardware level
- **Selective disclosure** — per-key access grants allow specific accounts to read specific records
- **EVM-compatible** — standard Solidity, Foundry, and OpenZeppelin work without modification
- **Immutable audit trail** — events are permanently indexed even when underlying data is encrypted

This matches how trade finance actually works: records are private between counterparties, auditable by regulators on demand.

---

## Security

- EIP-712 domain separation prevents cross-contract signature replay
- Per-nonce + used-signature map prevents replay within the same contract
- `ReentrancyGuard` on all state-modifying functions
- `Ownable` restricts admin operations to the Havona server address
- CBOR input validated on decode (malformed data reverts)

Security contact: security@havona.io

---

## Licence

MIT
