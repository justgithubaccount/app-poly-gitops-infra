#!/usr/bin/env bash
set -euo pipefail

kubectl wait --for=condition=Ready nodes --all --timeout=10m
kubectl -n kube-system wait --for=condition=Ready pods --all --timeout=15m
