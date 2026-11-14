#!/usr/bin/env bash
# Runs the EarmarkKit tests on this Mac with the swift.org toolchain (no Xcode here).
# The SwiftData `Store` target is skipped locally; CI (.github/workflows/ios.yml) runs everything.
set -euo pipefail
TC="${SWIFT_TOOLCHAIN:-$HOME/Library/Developer/Toolchains/swift-latest.xctoolchain}"
[ -x "$TC/usr/bin/swift" ] || { echo "No swift.org toolchain at $TC (install from swift.org)" >&2; exit 1; }
cd "$(dirname "$0")/EarmarkKit"
EARMARK_NO_SWIFTDATA=1 exec "$TC/usr/bin/swift" test "$@"
