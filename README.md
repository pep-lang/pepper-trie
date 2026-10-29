# pepper-trie

Compact tries for [Pepper](https://github.com/pep-lang/pepper): a fixed
trie over integer keys that a program holds as static data, for lookup
tables such as Unicode properties, and an ordered map and set of strings
after the HAT-trie, for when a hash map takes too much memory or a key
order or prefix search is needed. Its reference:
<https://pep-lang.github.io/pepper-trie/>.

One module, **`trie`**:

- **`StaticTrie<T>`** maps every key from 0 to `MAX_KEY` (0x10FFFF, so
  any code point) to a value of type `T` (`u8`, `u16` or `uint`) in O(1):
  one byte read for ASCII, two for the rest of the BMP, three above, and
  no allocation. It is laid out as ICU's `UCPTrie` is.
- **`StaticTrieBuilder`** takes values for keys and ranges of keys,
  merges equal blocks, and writes the trie as a Pepper expression
  (`StaticTrieData.source`) for a `const`: the program then holds it as
  static data, which costs only its bytes in the binary, no startup work,
  and nothing when no code reads it. It is for build scripts and
  generators.
- **`HatTrieMap<T>`** is a map from `String` to `T` that keeps its keys in
  byte order (code point order): `insert`, `get`, `try_get`, `contains`,
  `remove`, `count`, `trie[key]`, iteration in key order and
  `with_prefix(prefix)`. **`HatTrieSet`** is the same without values, as
  Tessil's `htrie_map` and `htrie_set` are.

```pepper
import trie;

main(): int {
    var words = trie.HatTrieMap<int>();
    words["pepper"] = 1;
    words["pear"] = 2;
    words["apple"] = 3;
    for (var (word, n) in words.with_prefix("pe")) {
        print($"{word} {n}");   # pear 2, then pepper 1
    }

    var widths = trie.StaticTrieBuilder(1);
    widths.set_range(0x4E00, 0x9FFF, 2);
    print(widths.build().reader<u8>().get(0x4E2D));   # 2
    return 0;
}
```

## A StaticTrie from a build script

A `StaticTrie` is made at build time: the package that reads it has a
build script (`build.pep`) that takes `trie` as a build-dependency, builds
the trie, and writes it into the package's generated module.
`examples/widths` is a whole package that does this:

```toml
# pep.toml
[build-dependencies]
trie = { github = "pep-lang/pepper-trie" }   # the build script builds the trie

[dependencies]
trie = { github = "pep-lang/pepper-trie" }   # the generated module names its type
```

```pepper
# build.pep
import [File, Path] from io;
import os;
import trie;

main(): int {
    var builder = trie.StaticTrieBuilder(1);
    builder.set_range(0x4E00, 0x9FFF, 2);
    var source = builder.build().source("u8");
    var out = Path(os.environment("PEP_OUT_DIR").value());
    File.write_text(out.join(Path("module.pep")), $"import trie;\n\nexport const WIDTHS = {source};\n");
    return 0;
}
```

```pepper
# main.pep
import generated;

main(): int {
    print(generated.WIDTHS.get(0x4E2D));   # 2
    return 0;
}
```

The build runs the script again only when what it reads changes (a
`pep:rerun-if-changed=` line names its data files), so a rebuild costs
nothing. `StaticTrieData.reader<T>()` reads a trie built in the same
program, for tests and for tables built at startup.

## How it works

**StaticTrie**, after ICU's `UCPTrie`: values sit in blocks of 64 keys
below `fast_limit` (0x10000 for `StaticTrieKind.Fast`, 0x1000 for
`Small`), found through a flat index, and in blocks of 16 above it, found
through two index levels; keys from `high_start` up all have
`high_value`. The builder stores each distinct block once and overlaps a
new block with the end of the one before where they agree. A string
literal holds only bytes up to 0x7F as static data
([pep-lang/pepper#298](https://github.com/pep-lang/pepper/issues/298)), so
every byte carries 7 bits, and an entry takes 1 to 5 bytes.

**HatTrieMap**, after Askitis and Sinha's HAT-trie ("HAT-trie: A
Cache-conscious Trie-based Data Structure for Strings", ACSC 2007) and
[Tessil's hat-trie](https://github.com/Tessil/hat-trie): a trie whose
leaves are array hash tables ("containers"). A container keeps the rest of
each key below it in a few byte arrays (a bucket is one array of
length-prefixed keys, each followed by its value's index), with no object
or pointer per key. Past the burst threshold (16384 keys, as in Tessil's)
a container bursts into a trie node with a container per next byte; keys
that all share a prefix burst into a chain of trie nodes at once. Lookups
walk the trie and hash in one container; in-order iteration sorts each
container as it reaches it; a prefix search walks to the prefix.

## Performance

`bench/run.sh`: 1,000,000 keys, best of 9, `-O`, Windows 11, Pepper
0.11.1. `words` are random lowercase words of 6 to 14 letters; `urls` are
URLs that share long prefixes (`https://github.com/issues/4711/...`). A
prefix search visits about 1/17,000 of the words (3 letters) or 1/48 of
the URLs; `HashMap` and `HashSet` scan every key for it, and sort every
key to visit them in order. Memory is the growth of the peak resident set
while inserting.

| structure | keys | insert ms | lookup ms | 20 prefix searches ms | in order ms | memory MB |
| --- | --- | --- | --- | --- | --- | --- |
| hat | words | 1212.9 | 323.9 | 1.50 | 273.2 | 39.2 |
| hash | words | 841.3 | 120.4 | 1829.71 | 1327.4 | 95.9 |
| map | words | 3997.7 | 2405.9 | 0.56 | 261.8 | 101.9 |
| hatset | words | 1173.3 | 263.3 | 1.45 | 269.0 | 27.6 |
| hashset | words | 819.8 | 122.1 | 2055.37 | 1218.0 | 79.9 |
| set | words | 3706.2 | 2654.2 | 0.79 | 205.3 | 93.6 |
| hat | urls | 1591.3 | 725.5 | 148.44 | 314.8 | 66.1 |
| hash | urls | 985.2 | 123.5 | 1851.28 | 974.5 | 131.6 |
| map | urls | 3275.3 | 1971.6 | 81.36 | 277.2 | 136.9 |
| hatset | urls | 1524.0 | 465.8 | 108.06 | 323.7 | 52.1 |
| hashset | urls | 971.8 | 144.8 | 2082.98 | 1256.7 | 115.6 |
| set | urls | 3400.2 | 2110.7 | 97.41 | 224.8 | 130.3 |

So, against the runtime's maps and sets:

- **Memory:** a `HatTrieMap` takes 38 to 50% of a `HashMap`'s or `Map`'s
  memory, a `HatTrieSet` 30 to 45% of a `HashSet`'s or `Set`'s.
- **Against `HashMap`:** lookups are 2 to 6 times slower (most for long
  keys with long shared prefixes, which walk many trie nodes) and inserts
  1.2 to 1.6 times slower, but a prefix search is 12 to 1,200 times faster, and
  in-order iteration 3 to 5 times faster than sorting the keys.
- **Against `Map` (a red-black tree):** inserts are 2 to 3 times faster
  and lookups 2.7 to 8 times faster; in-order iteration takes about as long,
  and a prefix search is slower when the prefix ends inside a large
  container, which it scans and sorts (a lower burst threshold, such as
  1024, makes that faster at some cost in memory).

Use a `HashMap` when only lookups matter and memory does not; a
`HatTrieMap` when memory, key order or prefix search do.

## Limits

- `StaticTrie` keys stop at 0x10FFFF, and its data takes 7 bits a byte
  until Pepper can hold raw bytes as static data (pep-lang/pepper#298).
- `HatTrieMap` and `HatTrieSet` keep trie nodes when their keys are
  removed (`clear` frees them), and copy keys into the containers, so
  iterating makes a new `String` for each key. It is the pure HAT-trie,
  not the hybrid one, as Tessil's is.

## Using it

This repository is a package: `pep.toml` marks its root, and its root
`module.pep` is the `trie` module. Add it to a project under the name
`trie`:

```sh
pepper package add pep-lang/pepper-trie --name trie            # to read tries and use HatTrieMap
pepper package add --build pep-lang/pepper-trie --name trie    # for a build script
```

which writes

```toml
[dependencies]
trie = { github = "pep-lang/pepper-trie" }
```

Without a project, put a folder named `trie` that holds (or links to)
this repository on the import path: `pepper build -I packages main.pep`.

## Tests

```sh
tests/run.sh path/to/pepper
```

runs the `[Test]` functions in `tests/` with `pepper test`: random keys
checked against the runtime's `Map` and `Set`, every key of random and
edge-case tries checked against their builder, and a trie held in a
constant. It then runs `examples/widths` and builds the benchmark
(`bench/run.sh path/to/pepper` runs it).

## Releasing

CI (`.github/workflows/ci.yml`) runs the tests on Linux, macOS and
Windows for every push to `main` and every pull request, and, when
`pep.toml` sets `minimum_toolchain`, on Linux with that toolchain too, so
the minimum it states stays true. It builds with `PEPPER_LOCKED=1`, the
same as `pepper test --locked`: a `pep.lock` out of date with `pep.toml`
fails the run, so commit `pep.lock` after changing a dependency. To
release, set
`version` in `pep.toml`, merge, then push the matching tag
(`git tag v1.0.0 && git push origin v1.0.0`): CI tests the tag,
publishes a GitHub release for it, and adds its reference (`pepper doc
package`, from the `##` doc comments) to the `gh-pages` branch, which
GitHub Pages serves once it is turned on for that branch (Settings,
Pages). `pepper package add` and `pepper package update` find versions by
their tags.

## License

Apache-2.0; see [LICENSE](LICENSE).
