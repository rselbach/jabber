#!/bin/bash
#
# Jabber Release Script
# Builds, signs, notarizes, and packages Jabber.app into a DMG.
#
# Prerequisites:
#   - Xcode Command Line Tools
#   - Developer ID Application certificate in keychain
#   - App-specific password for notarization stored in keychain:
#       xcrun notarytool store-credentials "jabber-notary" \
#         --apple-id "your@email.com" \
#         --team-id "YOUR_TEAM_ID" \
#         --password "app-specific-password"
#     Or APPLE_ID, APPLE_TEAM_ID, and APPLE_APP_PASSWORD in the environment.
#
# Usage:
#   ./scripts/release.sh [--skip-notarize]

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "${SCRIPT_DIR}")"
APP_NAME="Jabber"
BUNDLE_ID="com.rselbach.jabber"

# Configurable via environment
SIGNING_IDENTITY="${SIGNING_IDENTITY:-Developer ID Application}"
NOTARY_PROFILE="${NOTARY_PROFILE:-jabber-notary}"
BUILD_DIR="${PROJECT_ROOT}/.build/release-bundle"
DMG_DIR="${PROJECT_ROOT}/.build/dmg"

SKIP_NOTARIZE=false

usage() {
  echo "Usage: $0 [--skip-notarize]"
  echo ""
  echo "Options:"
  echo "  --skip-notarize  Skip notarization (for local testing)"
  exit 1
}

main() {
  parse_args "$@"

  validate_environment
  
  echo "==> Building ${APP_NAME} for release..."
  build_app
  
  echo "==> Creating app bundle..."
  create_bundle
  
  echo "==> Signing app bundle..."
  sign_app
  
  if [[ "${SKIP_NOTARIZE}" == "false" ]]; then
    echo "==> Creating DMG for notarization..."
    create_dmg
    
    echo "==> Notarizing DMG..."
    notarize_dmg
    
    echo "==> Stapling notarization ticket..."
    staple_dmg
  else
    echo "==> Skipping notarization (--skip-notarize)"
    echo "==> Creating DMG..."
    create_dmg
  fi
  
  echo ""
  echo "==> Release complete!"
  echo "    DMG: ${DMG_DIR}/${APP_NAME}.dmg"
}

require_env() {
  local name="$1"
  local value="${!name-}"
  if [[ -z "${value}" ]]; then
    echo "Error: ${name} is required." >&2
    exit 1
  fi
}

has_apple_id_notary_credentials() {
  [[ -n "${APPLE_ID-}" ]] && \
    [[ -n "${APPLE_TEAM_ID-}" ]] && \
    [[ -n "${APPLE_APP_PASSWORD-}" ]]
}

validate_notary_credentials() {
  if [[ -n "${APPLE_ID-}${APPLE_TEAM_ID-}${APPLE_APP_PASSWORD-}" ]]; then
    require_env APPLE_ID
    require_env APPLE_TEAM_ID
    require_env APPLE_APP_PASSWORD
    return
  fi

  require_env NOTARY_PROFILE
}

validate_environment() {
  local required_commands=(
    swift
    xcodebuild
    codesign
    hdiutil
    install_name_tool
    security
    xcrun
  )

  for cmd in "${required_commands[@]}"; do
    if ! command -v "${cmd}" >/dev/null 2>&1; then
      echo "Error: required command '${cmd}' not found." >&2
      exit 1
    fi
  done

  require_env SIGNING_IDENTITY

  if [[ "${SKIP_NOTARIZE}" == "false" ]]; then
    if ! xcrun --find notarytool >/dev/null 2>&1; then
      echo "Error: xcrun cannot find 'notarytool'." >&2
      exit 1
    fi

    if ! xcrun --find stapler >/dev/null 2>&1; then
      echo "Error: xcrun cannot find 'stapler'." >&2
      exit 1
    fi

    validate_notary_credentials
  fi
}

parse_args() {
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --skip-notarize)
        SKIP_NOTARIZE=true
        shift
        ;;
      -h|--help)
        usage
        ;;
      *)
        echo "Unknown option: $1" >&2
        usage
        ;;
    esac
  done
}

build_app() {
  cd "${PROJECT_ROOT}"
  swift build -c release
  ./scripts/build_mlx_metallib.sh release
}

create_bundle() {
  local app_bundle="${BUILD_DIR}/${APP_NAME}.app"
  local contents="${app_bundle}/Contents"
  local macos="${contents}/MacOS"
  local resources="${contents}/Resources"
  local frameworks="${contents}/Frameworks"
  
  rm -rf "${BUILD_DIR}"
  mkdir -p "${macos}" "${resources}" "${frameworks}"
  
  # Copy executable
  cp "${PROJECT_ROOT}/.build/release/Jabber" "${macos}/${APP_NAME}"

  # Copy MLX Metal shader library next to the executable for Qwen3-ASR.
  cp "${PROJECT_ROOT}/.build/release/mlx.metallib" "${macos}/mlx.metallib"
  
  # Copy Info.plist
  cp "${PROJECT_ROOT}/Info.plist" "${contents}/Info.plist"
  
  copy_sparkle_framework "${frameworks}"
  
  # Add rpath for Frameworks directory
  install_name_tool -add_rpath @executable_path/../Frameworks "${macos}/${APP_NAME}"
  
  # Copy resources from the build (SwiftPM bundles assets here)
  local bundle_resources="${PROJECT_ROOT}/.build/release/Jabber_Jabber.bundle"
  if [[ -d "${bundle_resources}" ]]; then
    cp -R "${bundle_resources}/"* "${resources}/"
  fi
  
  # Copy Assets.xcassets icons directly (actool compile)
  compile_assets "${resources}"
  
  echo "    Bundle created at: ${app_bundle}"
}

copy_sparkle_framework() {
  local frameworks_dir="$1"
  local sparkle_path="${PROJECT_ROOT}/.build/release/Sparkle.framework"

  if [[ ! -d "${sparkle_path}" ]]; then
    sparkle_path="${PROJECT_ROOT}/.build/artifacts/sparkle/Sparkle/Sparkle.xcframework/macos-arm64_x86_64/Sparkle.framework"
  fi

  if [[ ! -d "${sparkle_path}" ]]; then
    echo "Error: Sparkle.framework not found for release build." >&2
    echo "Run 'swift build -c release' and try again." >&2
    exit 1
  fi

  cp -R "${sparkle_path}" "${frameworks_dir}/"
  echo "    Copied Sparkle.framework from ${sparkle_path}"
}

compile_assets() {
  local resources_dir="$1"
  local assets_path="${PROJECT_ROOT}/Sources/Jabber/Assets.xcassets"
  
  if [[ -d "${assets_path}" ]]; then
    if ! xcrun actool "${assets_path}" \
      --compile "${resources_dir}" \
      --platform macosx \
      --minimum-deployment-target 26.0 \
      --app-icon AppIcon \
      --output-partial-info-plist "${BUILD_DIR}/AssetInfo.plist"; then
      echo "Error: failed to compile assets at ${assets_path}" >&2
      return 1
    fi
  fi
}

sign_app() {
  local app_bundle="${BUILD_DIR}/${APP_NAME}.app"
  local entitlements="${PROJECT_ROOT}/Jabber.entitlements"
  
  # Sign Sparkle.framework first
  codesign --force --options runtime --deep \
    --sign "${SIGNING_IDENTITY}" \
    "${app_bundle}/Contents/Frameworks/Sparkle.framework"

  # Sign MLX's Metal library before signing the executable/app bundle.
  # codesign treats files in Contents/MacOS as nested code objects.
  codesign --force --options runtime \
    --sign "${SIGNING_IDENTITY}" \
    "${app_bundle}/Contents/MacOS/mlx.metallib"
  
  # Sign the main executable
  codesign --force --options runtime \
    --entitlements "${entitlements}" \
    --sign "${SIGNING_IDENTITY}" \
    "${app_bundle}/Contents/MacOS/${APP_NAME}"
  
  # Sign the app bundle
  codesign --force --options runtime \
    --entitlements "${entitlements}" \
    --sign "${SIGNING_IDENTITY}" \
    "${app_bundle}"
  
  # Verify signature
  codesign --verify --deep --strict --verbose=2 "${app_bundle}"
  echo "    Signature verified"
}

create_dmg() {
  local app_bundle="${BUILD_DIR}/${APP_NAME}.app"
  local dmg_path="${DMG_DIR}/${APP_NAME}.dmg"
  local dmg_temp="${DMG_DIR}/${APP_NAME}-temp.dmg"
  
  rm -rf "${DMG_DIR}"
  mkdir -p "${DMG_DIR}"
  
  # Create a temporary DMG
  local staging="${DMG_DIR}/staging"
  mkdir -p "${staging}"
  cp -R "${app_bundle}" "${staging}/"
  
  # Create Applications symlink
  ln -s /Applications "${staging}/Applications"
  
  # Create DMG
  hdiutil create -volname "${APP_NAME}" \
    -srcfolder "${staging}" \
    -ov -format UDRW \
    "${dmg_temp}"
  
  # Convert to compressed read-only DMG
  hdiutil convert "${dmg_temp}" \
    -format UDZO \
    -imagekey zlib-level=9 \
    -o "${dmg_path}"
  
  rm -f "${dmg_temp}"
  rm -rf "${staging}"
  
  # Sign the DMG
  codesign --force --sign "${SIGNING_IDENTITY}" "${dmg_path}"
  
  echo "    DMG created at: ${dmg_path}"
}

notarize_dmg() {
  local dmg_path="${DMG_DIR}/${APP_NAME}.dmg"
  
  echo "    Submitting to Apple for notarization..."
  if has_apple_id_notary_credentials; then
    xcrun notarytool submit "${dmg_path}" \
      --apple-id "${APPLE_ID}" \
      --team-id "${APPLE_TEAM_ID}" \
      --password "${APPLE_APP_PASSWORD}" \
      --wait
  else
    xcrun notarytool submit "${dmg_path}" \
      --keychain-profile "${NOTARY_PROFILE}" \
      --wait
  fi
  
  echo "    Notarization complete"
}

staple_dmg() {
  local dmg_path="${DMG_DIR}/${APP_NAME}.dmg"
  
  xcrun stapler staple "${dmg_path}"
  echo "    Stapled notarization ticket to DMG"
}

main "$@"
