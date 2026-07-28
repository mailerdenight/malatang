#!/bin/zsh
set -euo pipefail

source "${0:A:h}/lib/common.sh"
load_ci_config

ARCHIVE_LOG="$LOG_DIR/archive.log"
exec > >(tee -a "$ARCHIVE_LOG") 2>&1

CURRENT_STAGE="Archive"
on_error() {
  local exit_code="$1"
  trap - ERR
  failure_guidance "$CURRENT_STAGE"
  exit "$exit_code"
}
trap 'on_error $?' ERR

require_command xcodebuild
require_command plutil
configure_xcode_auth_args

BUILD_NUMBER="${BUILD_NUMBER:-$(date -u '+%Y%m%d%H%M%S')}"
RUN_ID="${BUILD_NUMBER}"
ARCHIVE_ROOT="$ARTIFACTS_DIR/Archives"
EXPORT_ROOT="$ARTIFACTS_DIR/Export"
ARCHIVE_PATH="$ARCHIVE_ROOT/MalatangLog-${RUN_ID}.xcarchive"
EXPORT_PATH="$EXPORT_ROOT/$RUN_ID"
EXPORT_OPTIONS="$RUNTIME_DIR/ExportOptions-${RUN_ID}.plist"

mkdir -p "$ARCHIVE_ROOT" "$EXPORT_PATH"

section "Archive開始 (Build $BUILD_NUMBER)"
xcodebuild \
  -project "$PROJECT_PATH" \
  -scheme "$SCHEME" \
  -configuration "$CONFIGURATION" \
  -destination "generic/platform=iOS" \
  -archivePath "$ARCHIVE_PATH" \
  -allowProvisioningUpdates \
  "${XCODE_AUTH_ARGS[@]}" \
  CURRENT_PROJECT_VERSION="$BUILD_NUMBER" \
  clean archive

print
print "Archive Success"
print "Archive: $ARCHIVE_PATH"

CURRENT_STAGE="Export"
section "IPAを書き出し"
plutil -create xml1 "$EXPORT_OPTIONS"
plutil -insert method -string "app-store-connect" "$EXPORT_OPTIONS"
plutil -insert destination -string "export" "$EXPORT_OPTIONS"
plutil -insert signingStyle -string "automatic" "$EXPORT_OPTIONS"
plutil -insert teamID -string "$TEAM_ID" "$EXPORT_OPTIONS"
plutil -insert distributionBundleIdentifier -string "$BUNDLE_ID" "$EXPORT_OPTIONS"
plutil -insert uploadSymbols -bool true "$EXPORT_OPTIONS"
plutil -insert manageAppVersionAndBuildNumber -bool false "$EXPORT_OPTIONS"
if [[ "$TESTFLIGHT_INTERNAL_ONLY" == "true" ]]; then
  plutil -insert testFlightInternalTestingOnly -bool true "$EXPORT_OPTIONS"
fi

xcodebuild \
  -exportArchive \
  -archivePath "$ARCHIVE_PATH" \
  -exportPath "$EXPORT_PATH" \
  -exportOptionsPlist "$EXPORT_OPTIONS" \
  -allowProvisioningUpdates \
  "${XCODE_AUTH_ARGS[@]}"

IPA_FILES=("$EXPORT_PATH"/*.ipa(N))
if (( ${#IPA_FILES[@]} == 0 )); then
  print "ERROR: Export後のIPAが見つかりません: $EXPORT_PATH"
  return 1
fi

print -r -- "$ARCHIVE_PATH" > "$RUNTIME_DIR/latest-archive-path"
print -r -- "$IPA_FILES[1]" > "$RUNTIME_DIR/latest-ipa-path"
print -r -- "$BUILD_NUMBER" > "$RUNTIME_DIR/latest-build-number"

print
print "Export Success"
print "IPA:     $IPA_FILES[1]"
