#!/bin/bash
#
# Build a throwaway Jabber.app preview bundle to visually verify the app icon.
# Uses a unique bundle id per run so IconServices has no cached icon and
# renders the current Assets.xcassets icon. The bundle is NOT runnable
# (debug binary, no Sparkle / MediaRemoteAdapter / mlx.metallib copied in) —
# it exists only to show the icon in Finder.
#
# Usage: ./scripts/preview_icon.sh

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
readonly SCRIPT_DIR PROJECT_ROOT
readonly APP_NAME="JabberIconPreview"
readonly DEPLOYMENT_TARGET="26.0"
readonly PREVIEW_DIR="${TMPDIR:-/tmp}/jabber-icon-preview"

main() {
  echo "Building icon preview bundle..."

  local executable="${PROJECT_ROOT}/.build/debug/Jabber"
  if [[ ! -f "${executable}" ]]; then
    echo "  Debug binary not found; running swift build..." >&2
    (cd "${PROJECT_ROOT}" && swift build)
  fi

  local app_bundle="${PREVIEW_DIR}/${APP_NAME}.app"
  local contents="${app_bundle}/Contents"
  local macos_dir="${contents}/MacOS"
  local resources_dir="${contents}/Resources"

  rm -rf "${app_bundle}"
  mkdir -p "${macos_dir}" "${resources_dir}"

  # Executable (only needs to be a valid Mach-O so the bundle resolves).
  cp "${executable}" "${macos_dir}/Jabber"

  # Info.plist with a UNIQUE bundle id + bumped version. IconServices caches
  # by bundle id, so a fresh id each run forces it to render the actual icon
  # instead of a previously-cached one.
  cp "${PROJECT_ROOT}/Info.plist" "${contents}/Info.plist"
  local unique_id
  unique_id="com.rselbach.jabber.icon-preview.$(date +%s)"
  /usr/libexec/PlistBuddy -c "Set :CFBundleIdentifier ${unique_id}" "${contents}/Info.plist"
  /usr/libexec/PlistBuddy -c "Set :CFBundleVersion 9999" "${contents}/Info.plist"
  /usr/libexec/PlistBuddy -c "Set :CFBundleName Jabber Icon Preview" "${contents}/Info.plist"

  # Compile the asset catalog -> AppIcon.icns in Resources.
  if ! xcrun actool "${PROJECT_ROOT}/Sources/Jabber/Assets.xcassets" \
    --compile "${resources_dir}" \
    --platform macosx \
    --minimum-deployment-target "${DEPLOYMENT_TARGET}" \
    --app-icon AppIcon \
    --output-partial-info-plist "${PREVIEW_DIR}/AssetInfo.plist" >/dev/null; then
    echo "Error: actool failed to compile Assets.xcassets" >&2
    exit 1
  fi

  # Ad-hoc sign so the bundle is minimally valid (best-effort).
  codesign -s - "${app_bundle}" 2>/dev/null || echo "  (ad-hoc sign skipped)" >&2

  echo "  Preview bundle: ${app_bundle}"
  echo "  Bundle id:      ${unique_id}"
  echo "  (not runnable — icon preview only)"
  open -R "${app_bundle}"
}

main "$@"
