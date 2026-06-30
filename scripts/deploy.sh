#!/bin/bash
set -euo pipefail

# Build the lab image and deploy the Containerlab topology.
# This script is intended to run in the VBox Ubuntu environment used for
# validation, not in WSL-only editing environments.

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
LAB_NAME="xdp-vlan-policy-filter"
IMAGE="xdp-vlan-policy-filter:latest"
TOPOLOGY="${PROJECT_ROOT}/containerlab/xdp-vlan-policy-filter.clab.yml"

echo "=== Deploy ${LAB_NAME} ==="

echo ""
echo "== Step 1: Build Docker image =="
docker build -t "${IMAGE}" "${PROJECT_ROOT}"

echo ""
echo "== Step 2: Deploy containerlab topology =="
sudo containerlab deploy -t "${TOPOLOGY}"

echo ""
echo "== Step 3: Show lab status =="
sudo containerlab inspect -t "${TOPOLOGY}"

echo ""
echo "=== Deployment complete ==="
