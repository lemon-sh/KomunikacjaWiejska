#!/bin/bash
# Fails loudly when the installed Xcode cannot open this project.
# The project uses Xcode's JSON project format, so 27.2 is a hard minimum.
set -euo pipefail

required_major=27
required_minor=2

version="$(xcodebuild -version | awk 'NR == 1 { print $2 }')"
if [[ -z "${version}" ]]; then
    echo "error: unable to determine the Xcode version" >&2
    exit 1
fi

major="${version%%.*}"
rest="${version#*.}"
minor="${rest%%.*}"

if (( major < required_major || (major == required_major && minor < required_minor) )); then
    echo "error: Xcode ${required_major}.${required_minor}+ is required (found ${version})." >&2
    echo "error: this project uses project.xcproj and cannot be opened by older Xcode versions." >&2
    exit 1
fi

echo "Xcode ${version} OK (minimum ${required_major}.${required_minor})."
