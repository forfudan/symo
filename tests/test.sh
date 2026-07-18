#!/usr/bin/env bash
# Run the Symo test suite.
#
# Precompiles the package (via `pixi run package` if needed) and runs the Mojo
# test tool across the tests/ tree. Pass a subfolder name to run a subset,
# e.g. `bash tests/test.sh core`.
set -euo pipefail

cd "$(dirname "$0")"

TARGET="${1:-.}"

# The prebuilt package (symo.mojoc) is expected next to the tests so that
# `from symo import ...` resolves. Run `pixi run package` to (re)generate it.
if [[ ! -f "symo.mojoc" ]]; then
  echo "symo.mojoc not found in tests/. Run 'pixi run package' first." >&2
fi

pixi run mojo test -I . "${TARGET}"
