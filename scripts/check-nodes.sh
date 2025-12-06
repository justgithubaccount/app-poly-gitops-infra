#!/bin/bash
export KUBECONFIG=~/.kube/timeweb-config
kubectl get nodes -o wide
