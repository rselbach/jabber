#!/bin/bash
set -euo pipefail

CONFIG="${1:-debug}"
if [[ "${CONFIG}" != "debug" && "${CONFIG}" != "release" ]]; then
  echo "Usage: $0 [debug|release]" >&2
  exit 2
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "${SCRIPT_DIR}")"
UPSTREAM_SCRIPT="${PROJECT_ROOT}/.build/checkouts/speech-swift/scripts/build_mlx_metallib.sh"

if [[ ! -x "${UPSTREAM_SCRIPT}" ]]; then
  echo "Error: speech-swift metallib builder not found at ${UPSTREAM_SCRIPT}" >&2
  echo "Run swift build first so SwiftPM fetches dependencies." >&2
  exit 1
fi

BUILD_DIR="${PROJECT_ROOT}/.build" "${UPSTREAM_SCRIPT}" "${CONFIG}"
