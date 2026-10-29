#!/usr/bin/env bash
# Runs the HatTrieMap and HatTrieSet benchmark: each structure in turn, 9
# rounds, and prints the best time of each column (and the smallest memory).
#
# Usage: bench/run.sh [path/to/pepper] [count]   (default: pepper on PATH, 1000000)
set -euo pipefail

root="$(cd "$(dirname "$0")/.." && pwd)"
pepper="${1:-pepper}"
count="${2:-1000000}"
build="$(mktemp -d)"
trap 'rm -rf "$build"' EXIT

mkdir "$build/packages"
cp -r "$root" "$build/packages/trie"
"$pepper" build -O -I "$build/packages" "$root/bench/hat_trie/main.pep" -o "$build/bench"

for round in 1 2 3 4 5 6 7 8 9; do
    for kind in words urls; do
        for structure in hat hash map hatset hashset set; do
            "$build/bench" "$structure" "$kind" "$count"
        done
    done
done | awk '
    {
        key = $1 " " $2
        if (!(key in insert)) { order[++n] = key; insert[key] = $3; lookup[key] = $4; prefix[key] = $5; ordered[key] = $6; memory[key] = $7 }
        if ($3 < insert[key]) insert[key] = $3
        if ($4 < lookup[key]) lookup[key] = $4
        if ($5 < prefix[key]) prefix[key] = $5
        if ($6 < ordered[key]) ordered[key] = $6
        if ($7 < memory[key]) memory[key] = $7
    }
    END {
        print "| structure | keys | insert ms | lookup ms | 20 prefix searches ms | in order ms | memory MB |"
        print "| --- | --- | --- | --- | --- | --- | --- |"
        for (i = 1; i <= n; i++) {
            k = order[i]; split(k, part, " ")
            printf "| %s | %s | %s | %s | %s | %s | %.1f |\n", part[1], part[2], insert[k], lookup[k], prefix[k], ordered[k], memory[k] / 1048576
        }
    }'
