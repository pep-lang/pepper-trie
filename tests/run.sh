#!/usr/bin/env bash
# Runs the package's tests (the [Test] functions in tests/, with pepper test),
# runs the example and builds the benchmark.
#
# Usage: tests/run.sh [path/to/pepper]   (default: pepper on PATH)
set -euxo pipefail

root="$(cd "$(dirname "$0")/.." && pwd)"
pepper="${1:-pepper}"
build="$(mktemp -d)"
trap 'rm -rf "$build"' EXIT

# The package is the module `trie`: a folder of that name on the import path.
mkdir "$build/packages"
ln -s "$root" "$build/packages/trie"
"$pepper" test -I "$build/packages" "$root/tests"
# The example package's build script builds a StaticTrie into its
# generated module, with trie as a build-dependency.
(cd "$root/examples/widths" && "$pepper" run)
# The benchmark is run by hand (bench/run.sh); building it keeps it working.
"$pepper" build -I "$build/packages" "$root/bench/hat_trie/main.pep" -o "$build/bench"
