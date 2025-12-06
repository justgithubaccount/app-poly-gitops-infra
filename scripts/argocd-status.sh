#!/bin/bash
# ArgoCD Status Check Script
# Usage: ./scripts/argocd-status.sh [app-name]

set -e

KUBECONFIG="${KUBECONFIG:-$HOME/.kube/timeweb-config}"
export KUBECONFIG

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Icons (exported for potential subshells)
export CHECK="✓"
export CROSS="✗"
export WARN="⚠"
export SYNC="↻"

echo -e "${BLUE}═══════════════════════════════════════════════════════════════${NC}"
echo -e "${BLUE}                    ArgoCD Status Check                         ${NC}"
echo -e "${BLUE}═══════════════════════════════════════════════════════════════${NC}"
echo ""

# Check kubectl connection
echo -e "${YELLOW}[1/5] Checking cluster connection...${NC}"
if kubectl cluster-info &>/dev/null; then
    echo -e "  ${GREEN}${CHECK}${NC} Connected to cluster"
    CLUSTER=$(kubectl config current-context 2>/dev/null || echo "unknown")
    echo -e "  ${BLUE}Context:${NC} $CLUSTER"
else
    echo -e "  ${RED}${CROSS}${NC} Cannot connect to cluster"
    exit 1
fi
echo ""

# Check ArgoCD namespace
echo -e "${YELLOW}[2/5] Checking ArgoCD pods...${NC}"
ARGO_PODS=$(kubectl get pods -n argocd --no-headers 2>/dev/null | wc -l)
if [ "$ARGO_PODS" -gt 0 ]; then
    echo -e "  ${GREEN}${CHECK}${NC} ArgoCD is running ($ARGO_PODS pods)"

    # Show pod status
    kubectl get pods -n argocd --no-headers 2>/dev/null | while read line; do
        POD=$(echo "$line" | awk '{print $1}')
        STATUS=$(echo "$line" | awk '{print $3}')
        READY=$(echo "$line" | awk '{print $2}')

        if [ "$STATUS" == "Running" ]; then
            echo -e "    ${GREEN}${CHECK}${NC} $POD ($READY)"
        else
            echo -e "    ${RED}${CROSS}${NC} $POD - $STATUS"
        fi
    done
else
    echo -e "  ${RED}${CROSS}${NC} ArgoCD not found in namespace 'argocd'"
    exit 1
fi
echo ""

# List all applications
echo -e "${YELLOW}[3/5] ArgoCD Applications...${NC}"
echo ""

# Get applications with detailed status
if command -v argocd &>/dev/null && argocd app list &>/dev/null 2>&1; then
    # Use argocd CLI if available and logged in
    argocd app list --output wide 2>/dev/null | head -20
else
    # Fallback to kubectl
    kubectl get applications -n argocd -o custom-columns=\
'NAME:.metadata.name,SYNC:.status.sync.status,HEALTH:.status.health.status,REVISION:.status.sync.revision' 2>/dev/null || echo "  No applications found"
fi
echo ""

# Check specific app if provided
if [ -n "$1" ]; then
    APP_NAME="$1"
    echo -e "${YELLOW}[4/5] Application Details: ${APP_NAME}${NC}"
    echo ""

    # Get app status using kubectl jsonpath (no jq dependency)
    SYNC_STATUS=$(kubectl get application "$APP_NAME" -n argocd -o jsonpath='{.status.sync.status}' 2>/dev/null)

    if [ -n "$SYNC_STATUS" ]; then
        HEALTH_STATUS=$(kubectl get application "$APP_NAME" -n argocd -o jsonpath='{.status.health.status}' 2>/dev/null)
        REVISION=$(kubectl get application "$APP_NAME" -n argocd -o jsonpath='{.status.sync.revision}' 2>/dev/null | cut -c1-7)
        REPO=$(kubectl get application "$APP_NAME" -n argocd -o jsonpath='{.spec.source.repoURL}' 2>/dev/null)
        APP_PATH=$(kubectl get application "$APP_NAME" -n argocd -o jsonpath='{.spec.source.path}' 2>/dev/null)
        TARGET_REV=$(kubectl get application "$APP_NAME" -n argocd -o jsonpath='{.spec.source.targetRevision}' 2>/dev/null)

        # Sync status color
        case "$SYNC_STATUS" in
            "Synced") SYNC_COLOR=$GREEN ;;
            "OutOfSync") SYNC_COLOR=$YELLOW ;;
            *) SYNC_COLOR=$RED ;;
        esac

        # Health status color
        case "$HEALTH_STATUS" in
            "Healthy") HEALTH_COLOR=$GREEN ;;
            "Progressing") HEALTH_COLOR=$YELLOW ;;
            "Degraded"|"Missing") HEALTH_COLOR=$RED ;;
            *) HEALTH_COLOR=$YELLOW ;;
        esac

        echo -e "  ${BLUE}Sync Status:${NC}   ${SYNC_COLOR}${SYNC_STATUS}${NC}"
        echo -e "  ${BLUE}Health Status:${NC} ${HEALTH_COLOR}${HEALTH_STATUS}${NC}"
        echo -e "  ${BLUE}Revision:${NC}      ${REVISION:-N/A}"
        echo -e "  ${BLUE}Target Rev:${NC}    ${TARGET_REV:-HEAD}"
        echo -e "  ${BLUE}Repository:${NC}    ${REPO:-N/A}"
        echo -e "  ${BLUE}Path:${NC}          ${APP_PATH:-N/A}"
        echo ""

        # Show resources summary
        echo -e "  ${YELLOW}Resources:${NC}"
        kubectl get application "$APP_NAME" -n argocd \
            -o jsonpath='{range .status.resources[*]}    {.kind}/{.name}: {.status} ({.health.status}){"\n"}{end}' 2>/dev/null | head -15
        echo ""

        # Show conditions if any
        CONDITIONS=$(kubectl get application "$APP_NAME" -n argocd -o jsonpath='{.status.conditions[*].message}' 2>/dev/null)
        if [ -n "$CONDITIONS" ]; then
            echo -e "  ${YELLOW}Conditions:${NC} $CONDITIONS"
            echo ""
        fi
    else
        echo -e "  ${RED}${CROSS}${NC} Application '$APP_NAME' not found"
    fi
else
    echo -e "${YELLOW}[4/5] Skipped (no app specified)${NC}"
fi
echo ""

# Show recent sync history
echo -e "${YELLOW}[5/5] Recent Activity (last 5 events)...${NC}"
echo ""
kubectl get events -n argocd --sort-by='.lastTimestamp' 2>/dev/null | tail -6 | head -5 || echo "  No recent events"
echo ""

echo -e "${BLUE}═══════════════════════════════════════════════════════════════${NC}"
echo -e "${BLUE}  Tip: Run with app name for details: $0 dev-cluster         ${NC}"
echo -e "${BLUE}═══════════════════════════════════════════════════════════════${NC}"
