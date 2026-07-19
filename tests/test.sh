#!/usr/bin/env bash
# Run the Symo test suite.
#
# Compiles the library from `src/` (via `-I src`) and runs every `test_*.mojo`
# file's `main()` entry point. Pass a directory to scope the run, e.g.
# `bash tests/test.sh tests/core`.
set -euo pipefail

cd "$(dirname "$0")/.."

TARGET="${1:-tests}"

exit_code=0
while IFS= read -r -d '' file; do
  echo "=== $file ==="
  if ! pixi run mojo run -I src "$file"; then
    exit_code=1
  fi
done < <(find "$TARGET" -name 'test_*.mojo' -print0 | sort -z)

exit "$exit_code"
