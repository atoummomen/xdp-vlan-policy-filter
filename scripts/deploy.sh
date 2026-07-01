#!/bin/bash
set -euo pipefail

# Build the runtime lab image and deploy the Containerlab topology.
#
# This script is part of the validated workflow and is intended to run in the
# VBox Ubuntu environment where Docker, Containerlab, and kernel BPF support are
# available.

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
LAB_NAME="xdp-vlan-policy-filter"
IMAGE="xdp-vlan-policy-filter:latest"
TOPOLOGY="${PROJECT_ROOT}/containerlab/xdp-vlan-policy-filter.clab.yml"

echo "=== Deploy ${LAB_NAME} ==="

echo ""
echo "== Step 1: Build Docker image =="
# Build the image used by node1, filter-switch, and node2.
docker build -t "${IMAGE}" "${PROJECT_ROOT}"

echo ""
echo "== Step 2: Deploy containerlab topology =="
# Containerlab creates the three containers and connects their eth1/eth2 links
# according to containerlab/xdp-vlan-policy-filter.clab.yml.
sudo containerlab deploy -t "${TOPOLOGY}"

echo ""
echo "== Step 3: Show lab status =="
# Print the deployed nodes, container names, and link status for verification.
sudo containerlab inspect -t "${TOPOLOGY}"

echo ""
echo "=== Deployment complete ==="
