# Times HatTrieMap against the runtime's HashMap and Map (a red-black tree) on
# one data set, once, and prints a line of results; bench/run.sh runs it
# for each structure in turn and keeps the best of 9.
#
# Usage: main <hat|hash|map> <words|urls> [count] [burst threshold]
#
# Prints: structure, data set, then milliseconds to insert every key, look
# every key up, run 20 prefix searches, and visit every key in order, then
# the memory the structure added in bytes (peak resident set size after
# inserting, less before).

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
        _hosts = ["example.com", "pepper-lang.org", "docs.rs", "github.com", "en.wikipedia.org", "news.ycombinator.com"];
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
}

_milliseconds(start: os.Instant): double {
    return (os.Instant.now() - start).nanoseconds() as double / 1000000.0;
}

_prefixes(kind: String): String[] {
    var keys = Keys(kind);
    var prefixes = Array<String>();
    for (var i in 0..20) {
        var key = keys.next();
        prefixes.append(kind == "urls" ? key.substr_bytes(0, key.find("/", 8) as ulong + 1) + key.substr_bytes(key.find("/", 8) as ulong + 1, 2) : key.substr_bytes(0, 3));
    }
    return prefixes;
}

main(): int {
    var args = process.arguments();
    var structure = args[1];
    var kind = args[2];
    ulong count = args.count > 3 ? ulong.parse(args[3]).value() : 1000000;
    ulong burst = args.count > 4 ? ulong.parse(args[4]).value() : trie.DEFAULT_BURST_THRESHOLD;
    var prefixes = _prefixes(kind);
    var before = os.peak_memory();
    long found = 0;
    double insert_ms = 0;
    double lookup_ms = 0;
    double prefix_ms = 0;
    double ordered_ms = 0;
    ulong memory = 0;
    if (structure == "hat") {
        var map = trie.HatTrieMap<long>(burst);
        var keys = Keys(kind);
        var start = os.Instant.now();
        for (var i in 0..count) {
            map.insert(keys.next(), i as long);
        }
        insert_ms = _milliseconds(start);
        memory = os.peak_memory() - before;
        keys = Keys(kind);
        var probes = Array<String>(count);
        for (var i in 0..count) {
            probes.append(keys.next());
        }
        start = os.Instant.now();
        for (var probe in probes) {
            found += map.get(probe);
        }
        lookup_ms = _milliseconds(start);
        start = os.Instant.now();
        for (var prefix in prefixes) {
            for (var (key, value) in map.with_prefix(prefix)) {
                found += value;
            }
        }
        prefix_ms = _milliseconds(start);
        start = os.Instant.now();
        for (var (key, value) in map) {
            found += key.size as long;
        }
        ordered_ms = _milliseconds(start);
    } else if (structure == "hash") {
        var map = HashMap<String, long>();
        var keys = Keys(kind);
        var start = os.Instant.now();
        for (var i in 0..count) {
            map.insert(keys.next(), i as long);
        }
        insert_ms = _milliseconds(start);
        memory = os.peak_memory() - before;
        keys = Keys(kind);
        var probes = Array<String>(count);
        for (var i in 0..count) {
            probes.append(keys.next());
        }
        start = os.Instant.now();
        for (var probe in probes) {
            found += map.get(probe);
        }
        lookup_ms = _milliseconds(start);
        # A hash map has no order: a prefix search scans every key.
        start = os.Instant.now();
        for (var prefix in prefixes) {
            for (var (key, value) in map) {
                if (key.starts_with(prefix)) {
                    found += value;
                }
            }
        }
        prefix_ms = _milliseconds(start);
        start = os.Instant.now();
        var sorted = Array<String>(map.count as ulong);
        for (var (key, value) in map) {
            sorted.append(key);
        }
        sorted.sort_unstable();
        for (var key in sorted) {
            found += key.size as long;
        }
        ordered_ms = _milliseconds(start);
    } else {
        var map = Map<String, long>();
        var keys = Keys(kind);
        var start = os.Instant.now();
        for (var i in 0..count) {
            map.insert(keys.next(), i as long);
        }
        insert_ms = _milliseconds(start);
        memory = os.peak_memory() - before;
        keys = Keys(kind);
        var probes = Array<String>(count);
        for (var i in 0..count) {
            probes.append(keys.next());
        }
        start = os.Instant.now();
        for (var probe in probes) {
            found += map.get(probe);
        }
        lookup_ms = _milliseconds(start);
        start = os.Instant.now();
        for (var prefix in prefixes) {
            # Every key byte sorts before '{', so these are the keys under `prefix`.
            for (var (key, value) in map.range(prefix, prefix + "{")) {
                found += value;
            }
        }
        prefix_ms = _milliseconds(start);
        start = os.Instant.now();
        for (var (key, value) in map) {
            found += key.size as long;
        }
        ordered_ms = _milliseconds(start);
    }
    print($"{structure} {kind} {insert_ms:.1} {lookup_ms:.1} {prefix_ms:.2} {ordered_ms:.1} {memory} {found}");
    return 0;
}
