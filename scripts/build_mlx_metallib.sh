#!/bin/bash
#
# Build the MLX Metal shader library required by speech-swift/Qwen3-ASR.

set -euo pipefail

usage() {
  echo "Usage: $0 [debug|release]" >&2
}

ensure_metal_toolchain() {
  if xcrun metal -v >/dev/null 2>&1; then
    return
  fi

  echo "Error: Xcode Metal Toolchain is missing." >&2
  echo "Install it with: xcodebuild -downloadComponent MetalToolchain" >&2
  exit 1
}

main() {
  local config="${1:-debug}"
  if [[ "${config}" != "debug" && "${config}" != "release" ]]; then
    usage
    exit 2
  fi

  ensure_metal_toolchain

  local script_dir
  script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
  local project_root
  project_root="$(dirname "${script_dir}")"
  local upstream_script
  upstream_script="${project_root}/.build/checkouts/speech-swift/scripts/build_mlx_metallib.sh"

  if [[ ! -x "${upstream_script}" ]]; then
    echo "Error: speech-swift metallib builder not found at ${upstream_script}" >&2
    echo "Run swift build first so SwiftPM fetches dependencies." >&2
    exit 1
  fi

  BUILD_DIR="${project_root}/.build" "${upstream_script}" "${config}"
}

main "$@"
