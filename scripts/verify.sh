#!/bin/bash
set -euo pipefail

echo "==> Checking toolchain..."
./scripts/check-toolchain.sh

# Ensure simulator is booted so xcodebuild avoids cold-boot/shutdown overhead
xcrun simctl boot "iPhone 17" 2>/dev/null || true

echo "==> Running tests..."
xcodebuild test -project KomunikacjaWiejska.xcodeproj \
  -scheme KomunikacjaWiejska \
  -destination 'platform=iOS Simulator,name=iPhone 17' \
  CODE_SIGNING_ALLOWED=NO

echo "==> All verification checks passed!"

