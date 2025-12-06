#!/bin/bash
# Create SealedSecret from literals or file
# Usage:
#   ./scripts/create-sealed-secret.sh chat-openrouter chat-api OPENROUTER_API_KEY=sk-or-xxx
#   ./scripts/create-sealed-secret.sh chat-postgree chat-api DATABASE_URL=postgresql://...
#   ./scripts/create-sealed-secret.sh chat-github argocd --repo url=https://... username=xxx password=xxx

set -e

KUBECONFIG="${KUBECONFIG:-$HOME/.kube/timeweb-config}"
export KUBECONFIG

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Controller settings
CONTROLLER_NAME="${SEALED_SECRETS_CONTROLLER_NAME:-sealed-secrets}"
CONTROLLER_NAMESPACE="${SEALED_SECRETS_CONTROLLER_NAMESPACE:-kube-system}"

usage() {
    echo -e "${BLUE}Usage:${NC}"
    echo "  $0 <secret-name> <namespace> [--repo] KEY1=VALUE1 [KEY2=VALUE2 ...]"
    echo ""
    echo -e "${BLUE}Examples:${NC}"
    echo "  # Simple secret"
    echo "  $0 chat-openrouter chat-api OPENROUTER_API_KEY=sk-or-xxx"
    echo ""
    echo "  # Database connection"
    echo "  $0 chat-postgree chat-api DATABASE_URL='postgresql://user:pass@host:5432/db'"
    echo ""
    echo "  # Argo Image Updater repo secret (adds label)"
    echo "  $0 chat-github argocd --repo url=https://github.com/org/repo username=user password=token"
    echo ""
    echo -e "${BLUE}Environment:${NC}"
    echo "  KUBECONFIG                         - kubeconfig path (default: ~/.kube/timeweb-config)"
    echo "  SEALED_SECRETS_CONTROLLER_NAME     - controller name (default: sealed-secrets)"
    echo "  SEALED_SECRETS_CONTROLLER_NAMESPACE - controller namespace (default: kube-system)"
    exit 1
}

# Check args
if [ $# -lt 3 ]; then
    usage
fi

SECRET_NAME="$1"
NAMESPACE="$2"
shift 2

# Check for --repo flag
IS_REPO_SECRET=false
if [ "$1" == "--repo" ]; then
    IS_REPO_SECRET=true
    shift
fi

# Check kubeseal
if ! command -v kubeseal &>/dev/null; then
    echo -e "${RED}✗ kubeseal not found${NC}"
    echo ""
    echo "Install with:"
    echo "  wget https://github.com/bitnami-labs/sealed-secrets/releases/download/v0.32.2/kubeseal-0.32.2-linux-amd64.tar.gz"
    echo "  tar -xvzf kubeseal-0.32.2-linux-amd64.tar.gz"
    echo "  sudo install -m 755 kubeseal /usr/local/bin/kubeseal"
    exit 1
fi

# Verify controller is running
echo -e "${YELLOW}Checking SealedSecrets controller...${NC}"
if ! kubectl get pods -n "$CONTROLLER_NAMESPACE" -l app.kubernetes.io/name=sealed-secrets --no-headers 2>/dev/null | grep -q Running; then
    echo -e "${RED}✗ SealedSecrets controller not running in ${CONTROLLER_NAMESPACE}${NC}"
    exit 1
fi
echo -e "${GREEN}✓${NC} Controller found in ${CONTROLLER_NAMESPACE}"

# Build kubectl create secret command
KUBECTL_ARGS=()
for arg in "$@"; do
    if [[ "$arg" == *"="* ]]; then
        KUBECTL_ARGS+=("--from-literal=$arg")
    else
        echo -e "${RED}✗ Invalid argument: $arg (expected KEY=VALUE)${NC}"
        exit 1
    fi
done

if [ ${#KUBECTL_ARGS[@]} -eq 0 ]; then
    echo -e "${RED}✗ No key=value pairs provided${NC}"
    usage
fi

echo -e "${YELLOW}Creating SealedSecret...${NC}"
echo -e "  ${BLUE}Name:${NC}      $SECRET_NAME"
echo -e "  ${BLUE}Namespace:${NC} $NAMESPACE"
echo -e "  ${BLUE}Keys:${NC}      ${#KUBECTL_ARGS[@]}"
if [ "$IS_REPO_SECRET" == "true" ]; then
    echo -e "  ${BLUE}Type:${NC}      ArgoCD Repository Secret"
fi
echo ""

# Create the secret
if [ "$IS_REPO_SECRET" == "true" ]; then
    # For Argo Image Updater repo secrets - need the label
    kubectl create secret generic "$SECRET_NAME" \
        --namespace="$NAMESPACE" \
        "${KUBECTL_ARGS[@]}" \
        --dry-run=client -o json | \
    jq '.metadata.labels["argocd.argoproj.io/secret-type"]="repository"' | \
    kubeseal \
        --controller-name="$CONTROLLER_NAME" \
        --controller-namespace="$CONTROLLER_NAMESPACE" \
        --format yaml
else
    # Regular secret
    kubectl create secret generic "$SECRET_NAME" \
        --namespace="$NAMESPACE" \
        "${KUBECTL_ARGS[@]}" \
        --dry-run=client -o json | \
    kubeseal \
        --controller-name="$CONTROLLER_NAME" \
        --controller-namespace="$CONTROLLER_NAMESPACE" \
        --format yaml
fi

echo ""
echo -e "${GREEN}✓ SealedSecret created successfully${NC}"
echo ""
echo -e "${YELLOW}To save to file:${NC}"
echo "  $0 $SECRET_NAME $NAMESPACE ${*} > ${SECRET_NAME}-secrets.yaml"
