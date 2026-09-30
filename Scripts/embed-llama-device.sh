#!/bin/bash
set -euo pipefail
if [ "${PLATFORM_NAME:-}" != "iphoneos" ]; then
  exit 0
fi
SRC="${PROJECT_DIR}/Vendor/llama.xcframework/ios-arm64/llama.framework"
DST="${BUILT_PRODUCTS_DIR}/${FRAMEWORKS_FOLDER_PATH}"
mkdir -p "$DST"
ditto "$SRC" "$DST/llama.framework"
if [ -n "${EXPANDED_CODE_SIGN_IDENTITY:-}" ] && [ "${CODE_SIGNING_REQUIRED:-}" != "NO" ]; then
  /usr/bin/codesign --force --sign "${EXPANDED_CODE_SIGN_IDENTITY}" --preserve-metadata=identifier,entitlements,flags --timestamp=none "$DST/llama.framework"
fi
