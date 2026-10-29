## Compact tries: `StaticTrie<T>`, an immutable map from Unicode code
## points to small integers that a program holds as static data, and its
## `StaticTrieBuilder`, which a table generator runs.
##
## Bring it in with `import trie`.
##
## - `StaticTrieBuilder`: set values for code points and ranges, `build`
##   the data, and write it with `StaticTrieData.source` as a `const`
## - `StaticTrie<T>`: reads a code point's value in O(1), with no
##   allocation
##
## @example
##     import trie;
##
##     main(): int {
##         var builder = trie.StaticTrieBuilder(1);
##         builder.set_range(0x4E00, 0x9FFF, 2);
##         var widths = builder.build().reader<u8>();
##         print(widths.get(0x4E2D));   # 2
##         return 0;
##     }

# This file only gathers the module's public API from its other files.

import "hat_trie_map";
import "hat_trie_set";
import "static_trie";
import "static_trie_builder";

export StaticTrie;
export StaticTrieBuilder;
export StaticTrieData;
export StaticTrieKind;
export DEFAULT_BURST_THRESHOLD;
export HatTrieMap;
export HatTrieMapIterator;
export HatTrieSet;
export HatTrieSetIterator;
export MAX_KEY;
