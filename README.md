# pepper-trie

One paragraph for [Pepper](https://github.com/pep-lang/pepper): what the
package does and why someone would use it. Its reference:
<https://pep-lang.github.io/pepper-trie/>.

One module, **`trie`**:

- **`trie.greet(name)`** returns a greeting for `name`.
- **`trie.add(a, b)`** returns `a + b`, computed in C (`native/add.c`,
  which the `[native]` table in `pep.toml` compiles and links).

```pepper
import trie;

main(): int {
    print(trie.greet("Ada"));   # Hello, Ada!
    return 0;
}
```

## Limits

- What it does not do yet.

## Using it

This repository is a package: `pep.toml` marks its root, and its root
`module.pep` is the `trie` module. Add it to a project under the name
`trie`:

```sh
pepper package add pep-lang/pepper-trie --name trie
```

which writes

```toml
[dependencies]
trie = { github = "pep-lang/pepper-trie" }
```

Without a project, put a folder named `trie` that holds (or links to)
this repository on the import path: `pepper build -I packages main.pep`.
That builds no C, though: a package with a `[native]` table in its
`pep.toml` must be a dependency.

## Tests

```sh
tests/run.sh path/to/pepper
```

runs the `[Test]` functions in `tests/` with `pepper test`. A package only
the tests use goes in `[dev-dependencies]` (`pepper package add --dev
pep-lang/name`): projects that depend on this one do not fetch it.

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
