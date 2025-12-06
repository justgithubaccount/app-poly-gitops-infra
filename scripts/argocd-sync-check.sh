#!/bin/bash
# ArgoCD Sync Check - Wait for sync after merge
# Usage: ./scripts/argocd-sync-check.sh [app-name] [timeout-seconds]

set -e

KUBECONFIG="${KUBECONFIG:-$HOME/.kube/timeweb-config}"
export KUBECONFIG

APP_NAME="${1:-dev-cluster}"
TIMEOUT="${2:-120}"
INTERVAL=5

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

echo -e "${BLUE}═══════════════════════════════════════════════════════════════${NC}"
echo -e "${BLUE}        ArgoCD Sync Check: ${APP_NAME}                          ${NC}"
echo -e "${BLUE}═══════════════════════════════════════════════════════════════${NC}"
echo ""

# Get initial revision
INITIAL_REV=$(kubectl get application "$APP_NAME" -n argocd -o jsonpath='{.status.sync.revision}' 2>/dev/null | cut -c1-7)
echo -e "${YELLOW}Initial revision:${NC} $INITIAL_REV"
echo -e "${YELLOW}Waiting for sync (timeout: ${TIMEOUT}s)...${NC}"
echo ""

START_TIME=$(date +%s)
SYNCED=false

while true; do
    CURRENT_TIME=$(date +%s)
    ELAPSED=$((CURRENT_TIME - START_TIME))

    if [ $ELAPSED -ge $TIMEOUT ]; then
        echo -e "\n${RED}✗ Timeout reached after ${TIMEOUT}s${NC}"
        break
    fi

    # Get current status using kubectl jsonpath (no jq)
    SYNC_STATUS=$(kubectl get application "$APP_NAME" -n argocd -o jsonpath='{.status.sync.status}' 2>/dev/null)
    HEALTH_STATUS=$(kubectl get application "$APP_NAME" -n argocd -o jsonpath='{.status.health.status}' 2>/dev/null)
    CURRENT_REV=$(kubectl get application "$APP_NAME" -n argocd -o jsonpath='{.status.sync.revision}' 2>/dev/null | cut -c1-7)
    OPERATION=$(kubectl get application "$APP_NAME" -n argocd -o jsonpath='{.status.operationState.phase}' 2>/dev/null)

    # Progress indicator
    printf "\r  [%3ds] Sync: %-10s | Health: %-12s | Rev: %s | Op: %s    " \
        "$ELAPSED" "${SYNC_STATUS:-Unknown}" "${HEALTH_STATUS:-Unknown}" "${CURRENT_REV:-N/A}" "${OPERATION:-None}"

    # Check if synced and healthy
    if [ "$SYNC_STATUS" == "Synced" ] && [ "$HEALTH_STATUS" == "Healthy" ]; then
        SYNCED=true
        echo ""
        echo ""
        echo -e "${GREEN}✓ Application synced and healthy!${NC}"
        break
    fi

    # Check for errors
    if [ "$HEALTH_STATUS" == "Degraded" ]; then
        echo ""
        echo ""
        echo -e "${RED}✗ Application is degraded${NC}"

        # Show error details
        echo -e "${YELLOW}Conditions:${NC}"
        kubectl get application "$APP_NAME" -n argocd -o jsonpath='{range .status.conditions[*]}  [{.type}] {.message}{"\n"}{end}' 2>/dev/null
        break
    fi

    sleep $INTERVAL
done

echo ""

# Final status
echo -e "${BLUE}═══════════════════════════════════════════════════════════════${NC}"
if [ "$SYNCED" == "true" ]; then
    echo -e "${GREEN}  Result: SUCCESS${NC}"
    echo -e "  Revision: $INITIAL_REV → $CURRENT_REV"

    # Show what was deployed
    echo ""
    echo -e "${YELLOW}Deployed resources:${NC}"
    kubectl get application "$APP_NAME" -n argocd \
        -o jsonpath='{range .status.resources[*]}  {.kind}/{.name} [{.status}]{"\n"}{end}' 2>/dev/null | head -10

    exit 0
else
    echo -e "${RED}  Result: FAILED${NC}"
    echo ""

    # Show all resources with status
    echo -e "${YELLOW}Resources status:${NC}"
    kubectl get application "$APP_NAME" -n argocd \
        -o jsonpath='{range .status.resources[*]}  {.kind}/{.name}: sync={.status} health={.health.status}{"\n"}{end}' 2>/dev/null | head -15

    exit 1
fi
