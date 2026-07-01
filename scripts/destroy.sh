#!/bin/bash
set -euo pipefail

# Cleanup helper for the validated lab environment.
#
# It removes the Containerlab topology and then removes the local Docker image
# used by node1, filter-switch, and node2.

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
LAB_NAME="xdp-vlan-policy-filter"
IMAGE="xdp-vlan-policy-filter:latest"
TOPOLOGY="${PROJECT_ROOT}/containerlab/xdp-vlan-policy-filter.clab.yml"

echo "=== Destroy ${LAB_NAME} ==="

echo ""
echo "== Step 1: Destroy containerlab topology =="
# --cleanup removes Containerlab-created files and network resources.
# "|| true" keeps the script safe if the lab is already absent.
sudo containerlab destroy -t "${TOPOLOGY}" --cleanup || true

echo ""
echo "== Step 2: Remove Docker image =="
# Remove the local lab image only if it exists.
if docker images "${IMAGE}" --format '{{.Repository}}:{{.Tag}}' | grep -q "^${IMAGE}$"; then
    docker rmi "${IMAGE}"
    echo "[OK] Docker image removed: ${IMAGE}"
else
    echo "[OK] Docker image already absent: ${IMAGE}"
fi

echo ""
echo "=== Cleanup complete ==="
