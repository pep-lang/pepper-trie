# Times HatTrieMap and HatTrieSet against the runtime's HashMap, Map (a
# red-black tree), HashSet and Set on one data set, once, and prints a line
# of results; bench/run.sh runs each in turn and keeps the best of 9.
#
# Usage: main <structure> <words|urls> [count] [burst threshold]
#
# <structure> is hat, hash or map (maps from String to long), or hatset,
# hashset or set (sets of String).
#
# Prints: structure, data set, then milliseconds to insert every key, look
# every key up, run 20 prefix searches, and visit every key in order, then
# the memory the structure added in bytes (peak resident set size after
# inserting, less before), then a checksum that must agree across
# structures of a kind.

import os;
import process;
import random;
import trie;

const LETTERS = "abcdefghijklmnopqrstuvwxyz";

# Keys of `kind`, the same for every run.
struct Keys {
    var kind: String;
    var _generator: random.Generator;
    var _hosts: String[];
    var _sections: String[];

    construct(kind: String) {
        this.kind = kind;
        _generator = random.Generator(7);
        _hosts = [
            "example.com", "pepper-lang.org", "docs.rs", "github.com", "en.wikipedia.org", "news.ycombinator.com"
        ];
        _sections = ["wiki", "issues", "pull", "blob/main", "tree/main", "search", "users", "items"];
    }

    next(): String {
        var out = StringBuilder();
        if (kind == "urls") {
            out.append("https://").append(_hosts[_generator.next_int(0..6) as ulong]).append("/");
            out.append(_sections[_generator.next_int(0..8) as ulong]).append("/");
            out.append(to_string(_generator.next_int(0..100000))).append("/");
        }
        var size = _generator.next_int(6..15);
        for (var i in 0..size) {
            out.append(LETTERS[_generator.next_int(0..26) as ulong]);
        }
        return out.to_string();
    }

    take(count: ulong): String[] {
        var keys = Array<String>(count);
        for (var i in 0..count) {
            keys.append(next());
        }
        return keys;
    }
}

# What one run measured.
struct Run {
    var insert_ms: double;
    var lookup_ms: double;
    var prefix_ms: double;
    var ordered_ms: double;
    var memory: ulong;
    var checksum: long;
}

# Times `step` and returns its milliseconds.
_time(step: () => void): double {
    var start = os.Instant.now();
    step();
    return (os.Instant.now() - start).nanoseconds() as double / 1000000.0;
}

# The 20 prefixes the prefix searches look for: a word key's first 3
# bytes, or a URL's host and 2 more bytes.
_prefixes(kind: String): String[] {
    var keys = Keys(kind);
    var prefixes = Array<String>();
    for (var i in 0..20) {
        var key = keys.next();
        var size = kind == "urls" ? key.find("/", 8) as ulong + 3 : 3;
        prefixes.append(key.substr_bytes(0, size));
    }
    return prefixes;
}

# Inserts `count` keys of `kind` with `insert`, measuring memory, then times
# looking them all up with `lookup`.
_fill(run: Run, kind: String, count: ulong, insert: (String, long) => void, lookup: (String) => long) {
    var keys = Keys(kind);
    var before = os.peak_memory();
    run.insert_ms = _time(() => {
        for (var i in 0..count) {
            insert(keys.next(), i as long);
        }
    });
    run.memory = os.peak_memory() - before;
    var probes = Keys(kind).take(count);
    run.lookup_ms = _time(() => {
        for (var probe in probes) {
            run.checksum += lookup(probe);
        }
    });
}

main(): int {
    var args = process.arguments();
    var structure = args[1];
    var kind = args[2];
    ulong count = args.count > 3 ? ulong.parse(args[3]).value() : 1000000;
    ulong burst = args.count > 4 ? ulong.parse(args[4]).value() : trie.DEFAULT_BURST_THRESHOLD;
    var prefixes = _prefixes(kind);
    var run = Run();
    if (structure == "hat") {
        var map = trie.HatTrieMap<long>(burst);
        _fill(run, kind, count, (key, value) => map.insert(key, value), (key) => map.get(key));
        run.prefix_ms = _time(() => {
            for (var prefix in prefixes) {
                for (var (key, value) in map.with_prefix(prefix)) {
                    run.checksum += value;
                }
            }
        });
        run.ordered_ms = _time(() => {
            for (var (key, value) in map) {
                run.checksum += key.size as long;
            }
        });
    } else if (structure == "hash") {
        var map = HashMap<String, long>();
        _fill(run, kind, count, (key, value) => map.insert(key, value), (key) => map.get(key));
        # A hash map has no order: a prefix search scans every key.
        run.prefix_ms = _time(() => {
            for (var prefix in prefixes) {
                for (var (key, value) in map) {
                    if (key.starts_with(prefix)) {
                        run.checksum += value;
                    }
                }
            }
        });
        run.ordered_ms = _time(() => {
            var sorted = Array<String>(map.count as ulong);
            for (var (key, value) in map) {
                sorted.append(key);
            }
            sorted.sort_unstable();
            for (var key in sorted) {
                run.checksum += key.size as long;
            }
        });
    } else if (structure == "map") {
        var map = Map<String, long>();
        _fill(run, kind, count, (key, value) => map.insert(key, value), (key) => map.get(key));
        run.prefix_ms = _time(
            () => {
                for (var prefix in prefixes) {
                    # Every key byte sorts before '{', so these are the keys under `prefix`.
                    for (var (key, value) in map.range(prefix, prefix + "{")) {
                        run.checksum += value;
                    }
                }
            }
        );
        run.ordered_ms = _time(() => {
            for (var (key, value) in map) {
                run.checksum += key.size as long;
            }
        });
    } else if (structure == "hatset") {
        var set = trie.HatTrieSet(burst);
        _fill(run, kind, count, (key, value) => set.insert(key), (key) => set.contains(key) ? 1 : 0);
        run.prefix_ms = _time(() => {
            for (var prefix in prefixes) {
                for (var key in set.with_prefix(prefix)) {
                    run.checksum += key.size as long;
                }
            }
        });
        run.ordered_ms = _time(() => {
            for (var key in set) {
                run.checksum += key.size as long;
            }
        });
    } else if (structure == "hashset") {
        var set = HashSet<String>();
        _fill(run, kind, count, (key, value) => set.insert(key), (key) => set.contains(key) ? 1 : 0);
        run.prefix_ms = _time(() => {
            for (var prefix in prefixes) {
                for (var key in set) {
                    if (key.starts_with(prefix)) {
                        run.checksum += key.size as long;
                    }
                }
            }
        });
        run.ordered_ms = _time(() => {
            var sorted = Array<String>(set.count as ulong);
            for (var key in set) {
                sorted.append(key);
            }
            sorted.sort_unstable();
            for (var key in sorted) {
                run.checksum += key.size as long;
            }
        });
    } else {
        var set = Set<String>();
        _fill(run, kind, count, (key, value) => set.insert(key), (key) => set.contains(key) ? 1 : 0);
        run.prefix_ms = _time(() => {
            for (var prefix in prefixes) {
                for (var key in set.range(prefix, prefix + "{")) {
                    run.checksum += key.size as long;
                }
            }
        });
        run.ordered_ms = _time(() => {
            for (var key in set) {
                run.checksum += key.size as long;
            }
        });
    }
    var line = $"{structure} {kind} {run.insert_ms:.1} {run.lookup_ms:.1} {run.prefix_ms:.2} {run.ordered_ms:.1}";
    print($"{line} {run.memory} {run.checksum}");
    return 0;
}
