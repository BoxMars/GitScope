#!/bin/bash
# Build and launch GitScope.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
"$ROOT/scripts/build.sh" "${1:-debug}"
open "$ROOT/build/GitScope.app"
