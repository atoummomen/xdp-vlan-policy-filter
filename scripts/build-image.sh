#!/bin/bash
set -euo pipefail

# Optional helper for building an image from a named lab directory under
# containerlab/. The final validated workflow uses scripts/deploy.sh instead.
# Usage: ./build-image.sh <lab-name>
# Example: ./build-image.sh basic-lab

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "${SCRIPT_DIR}")"

LAB_NAME="${1:-}"
if [[ -z "${LAB_NAME}" ]]; then
    echo "Usage: $0 <lab-name>"
    echo ""
    echo "Available labs:"
    for d in "${PROJECT_ROOT}/containerlab"/*/; do
        [[ -f "${d}/Dockerfile" ]] && echo "  $(basename "${d}")"
    done
    exit 1
fi

LAB_DIR="${PROJECT_ROOT}/containerlab/${LAB_NAME}"
if [[ ! -d "${LAB_DIR}" ]]; then
    echo "[ERROR] Lab not found: ${LAB_DIR}"
    exit 1
fi

IMAGE="clab-softnet-${LAB_NAME}:latest"

echo "=== Build Docker Image for ${LAB_NAME} ==="
echo ""
echo "== Building ${IMAGE} =="
docker build -t "${IMAGE}" "${LAB_DIR}"

echo ""
echo "== Verification =="
docker images "${IMAGE}"

echo ""
echo "=== Build Complete ==="
echo "Image: ${IMAGE}"
echo ""
echo "Next step: cd ${LAB_DIR} && ./deploy.sh"
