#!/bin/zsh
set -euo pipefail

source "${0:A:h}/lib/common.sh"
load_ci_config

BUILD_LOG="$LOG_DIR/build.log"
exec > >(tee -a "$BUILD_LOG") 2>&1

CURRENT_STAGE="Git Sync"
on_error() {
  local exit_code="$1"
  trap - ERR
  failure_guidance "$CURRENT_STAGE"
  exit "$exit_code"
}
trap 'on_error $?' ERR

section "Build開始"
print "Repository: $REPO_PATH"
print "Project:    $PROJECT_PATH"
print "Scheme:     $SCHEME"

require_command xcodebuild
sync_latest_code

CURRENT_STAGE="Build"
configure_xcode_auth_args

section "依存関係を解決"
xcodebuild \
  -resolvePackageDependencies \
  -project "$PROJECT_PATH" \
  -scheme "$SCHEME" \
  "${XCODE_AUTH_ARGS[@]}"

section "Release構成をBuild"
xcodebuild \
  -project "$PROJECT_PATH" \
  -scheme "$SCHEME" \
  -configuration "$CONFIGURATION" \
  -destination "generic/platform=iOS" \
  -derivedDataPath "$DERIVED_DATA_DIR" \
  -allowProvisioningUpdates \
  "${XCODE_AUTH_ARGS[@]}" \
  clean build

print
print "Build Success"
