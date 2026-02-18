#!/bin/bash

# Deploy Havona Smart Contracts to Oasis Sapphire
#
# Unlike TEN, Sapphire supports 'forge script' natively — no need for
# individual 'forge create' calls. This deploys all contracts atomically.
#
# Prerequisites:
#   1. Foundry installed (forge, cast)
#   2. ROSE tokens for gas (testnet faucet: https://faucet.testnet.oasis.io/)
#   3. Private key set via --private-key or PRIVATE_KEY env var
#
# Usage:
#   ./deploy_sapphire.sh --private-key 0x...              # Testnet (default)
#   ./deploy_sapphire.sh --private-key 0x... --mainnet     # Mainnet
#   ./deploy_sapphire.sh --dry-run                         # Build only, no broadcast

set -e

# ============================================================================
# NETWORK CONFIGURATION
# ============================================================================
SAPPHIRE_TESTNET_RPC="https://testnet.sapphire.oasis.io"
SAPPHIRE_MAINNET_RPC="https://sapphire.oasis.io"
SAPPHIRE_TESTNET_CHAIN_ID=23295
SAPPHIRE_MAINNET_CHAIN_ID=23294
SAPPHIRE_TESTNET_EXPLORER="https://explorer.oasis.io/testnet/sapphire"
SAPPHIRE_MAINNET_EXPLORER="https://explorer.oasis.io/mainnet/sapphire"

# ============================================================================
# DEFAULTS
# ============================================================================
NETWORK="testnet"
RPC_URL="$SAPPHIRE_TESTNET_RPC"
CHAIN_ID="$SAPPHIRE_TESTNET_CHAIN_ID"
EXPLORER="$SAPPHIRE_TESTNET_EXPLORER"
DRY_RUN=false
PRIVATE_KEY="${PRIVATE_KEY:-}"

# Paths
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
CONTRACTS_DIR="$REPO_ROOT"

# Colors
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
CYAN='\033[0;36m'
NC='\033[0m'

print_msg() { echo -e "${1}${2}${NC}"; }

# ============================================================================
# PARSE ARGUMENTS
# ============================================================================
while [[ $# -gt 0 ]]; do
    case $1 in
        --mainnet)
            NETWORK="mainnet"
            RPC_URL="$SAPPHIRE_MAINNET_RPC"
            CHAIN_ID="$SAPPHIRE_MAINNET_CHAIN_ID"
            EXPLORER="$SAPPHIRE_MAINNET_EXPLORER"
            shift ;;
        --testnet)
            shift ;;
        --private-key)
            PRIVATE_KEY="$2"
            shift 2 ;;
        --dry-run)
            DRY_RUN=true
            shift ;;
        *)
            print_msg "$RED" "Unknown argument: $1"
            exit 1 ;;
    esac
done

# ============================================================================
# PREFLIGHT CHECKS
# ============================================================================
print_msg "$CYAN" "============================================"
print_msg "$CYAN" "  Havona Deploy -> Oasis Sapphire ($NETWORK)"
print_msg "$CYAN" "============================================"
echo ""

# Check forge
if ! command -v forge &>/dev/null; then
    print_msg "$RED" "forge not found. Install Foundry: https://book.getfoundry.sh"
    exit 1
fi

# Check cast
if ! command -v cast &>/dev/null; then
    print_msg "$RED" "cast not found. Install Foundry: https://book.getfoundry.sh"
    exit 1
fi

# Check private key
if [ -z "$PRIVATE_KEY" ]; then
    print_msg "$RED" "Private key required. Use --private-key 0x... or set PRIVATE_KEY env var"
    exit 1
fi

# Derive account address
ACCOUNT=$(cast wallet address "$PRIVATE_KEY" 2>/dev/null)
if [ -z "$ACCOUNT" ]; then
    print_msg "$RED" "Invalid private key"
    exit 1
fi

print_msg "$GREEN" "Network:  Sapphire $NETWORK"
print_msg "$GREEN" "RPC:      $RPC_URL"
print_msg "$GREEN" "Chain ID: $CHAIN_ID"
print_msg "$GREEN" "Account:  $ACCOUNT"
echo ""

# Verify chain connectivity
print_msg "$YELLOW" "Checking chain connectivity..."
ACTUAL_CHAIN_ID=$(cast chain-id --rpc-url "$RPC_URL" 2>/dev/null || echo "FAIL")
if [ "$ACTUAL_CHAIN_ID" = "FAIL" ]; then
    print_msg "$RED" "Cannot connect to $RPC_URL"
    exit 1
fi
if [ "$ACTUAL_CHAIN_ID" != "$CHAIN_ID" ]; then
    print_msg "$RED" "Chain ID mismatch: expected $CHAIN_ID, got $ACTUAL_CHAIN_ID"
    exit 1
fi
print_msg "$GREEN" "Chain ID verified: $ACTUAL_CHAIN_ID"

# Check balance
BALANCE_WEI=$(cast balance "$ACCOUNT" --rpc-url "$RPC_URL" 2>/dev/null || echo "0")
BALANCE_ETH=$(echo "scale=6; $BALANCE_WEI / 1000000000000000000" | bc 2>/dev/null || echo "0")
print_msg "$GREEN" "Balance:  $BALANCE_ETH ROSE"

if [ "$BALANCE_WEI" = "0" ]; then
    print_msg "$RED" "Account has zero ROSE. Get testnet tokens: https://faucet.testnet.oasis.io/"
    exit 1
fi

# Check recent blocks for transaction processing
print_msg "$YELLOW" "Checking block activity..."
BLOCK_HEX=$(cast block-number --rpc-url "$RPC_URL" 2>/dev/null)
print_msg "$GREEN" "Current block: $BLOCK_HEX"

echo ""

if $DRY_RUN; then
    print_msg "$YELLOW" "DRY RUN - building contracts only, no broadcast"
    echo ""
fi

# ============================================================================
# BUILD
# ============================================================================
print_msg "$YELLOW" "Building contracts..."
cd "$CONTRACTS_DIR"

if [ ! -d "lib/forge-std" ]; then
    print_msg "$YELLOW" "Installing forge-std..."
    forge install foundry-rs/forge-std --no-commit
fi

forge build
print_msg "$GREEN" "Build successful"
echo ""

# ============================================================================
# DEPLOY
# ============================================================================
if $DRY_RUN; then
    print_msg "$GREEN" "Dry run complete. Contracts built successfully."
    print_msg "$YELLOW" "To deploy: remove --dry-run flag"
    exit 0
fi

print_msg "$YELLOW" "Deploying contracts via forge script..."
print_msg "$YELLOW" "(This deploys P256Verifier + HavonaPersistor atomically)"
echo ""

DEPLOY_OUTPUT=$(PRIVATE_KEY="$PRIVATE_KEY" forge script script/DeployPersistor.s.sol:DeployPersistor \
    --rpc-url "$RPC_URL" \
    --private-key "$PRIVATE_KEY" \
    --broadcast \
    -vvv 2>&1) || {
    print_msg "$RED" "Deployment failed:"
    echo "$DEPLOY_OUTPUT"
    exit 1
}

echo "$DEPLOY_OUTPUT"
echo ""

# Extract contract addresses from output
PERSISTOR_ADDRESS=$(echo "$DEPLOY_OUTPUT" | grep "PERSISTOR_ADDRESS:" | awk '{print $2}')
P256_ADDRESS=$(echo "$DEPLOY_OUTPUT" | grep "P256_VERIFIER_ADDRESS:" | awk '{print $2}')

# Fallback: extract from forge broadcast
if [ -z "$PERSISTOR_ADDRESS" ]; then
    PERSISTOR_ADDRESS=$(echo "$DEPLOY_OUTPUT" | grep -oP '(?<=Contract Address: )0x[a-fA-F0-9]{40}' | tail -1)
fi

# ============================================================================
# SAVE DEPLOYMENT INFO
# ============================================================================
TIMESTAMP=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
DEPLOY_FILE="$CONTRACTS_DIR/deployments/sapphire-$NETWORK.json"

cat > "$DEPLOY_FILE" << EOF
# Havona Sapphire Deployment
# Generated: $TIMESTAMP
# Network: Sapphire $NETWORK (chain $CHAIN_ID)
# Deployer: $ACCOUNT

PERSISTOR_ADDRESS=$PERSISTOR_ADDRESS
P256_VERIFIER_ADDRESS=$P256_ADDRESS
CHAIN_ID=$CHAIN_ID
RPC_URL=$RPC_URL
EXPLORER=$EXPLORER
EOF

print_msg "$CYAN" "============================================"
print_msg "$CYAN" "  DEPLOYMENT COMPLETE"
print_msg "$CYAN" "============================================"
print_msg "$GREEN" "Network:    Sapphire $NETWORK"
print_msg "$GREEN" "Persistor:  $PERSISTOR_ADDRESS"
print_msg "$GREEN" "P256:       $P256_ADDRESS"
print_msg "$GREEN" "Deployer:   $ACCOUNT"
print_msg "$GREEN" "Info saved: $DEPLOY_FILE"
echo ""
print_msg "$YELLOW" "Next steps:"
echo "1. Update .env.sapphire with CONTRACT_ADDRESS=$PERSISTOR_ADDRESS"
echo "2. Update .env.sapphire with P256_VERIFIER_ADDRESS=$P256_ADDRESS"
echo "3. Start Havona: ./tools/start-havona.sh --local (with .env.sapphire)"
if [ -n "$PERSISTOR_ADDRESS" ]; then
    echo "4. Verify on explorer: $EXPLORER/address/$PERSISTOR_ADDRESS"
fi
