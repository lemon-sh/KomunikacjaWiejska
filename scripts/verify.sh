#!/bin/bash
set -euo pipefail

echo "==> Checking toolchain..."
./scripts/check-toolchain.sh

echo "==> Building project..."
xcodebuild -project KomunikacjaWiejska.xcodeproj \
  -scheme KomunikacjaWiejska \
  -destination 'generic/platform=iOS Simulator' \
  CODE_SIGNING_ALLOWED=NO build

echo "==> Running tests..."
xcodebuild test -project KomunikacjaWiejska.xcodeproj \
  -scheme KomunikacjaWiejska \
  -destination 'platform=iOS Simulator,name=iPhone 17' \
  CODE_SIGNING_ALLOWED=NO

echo "==> All verification checks passed!"

