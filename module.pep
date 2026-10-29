## Compact tries: `CodePointTrie<T>`, an immutable map from Unicode code
## points to small integers that a program holds as static data, and its
## `CodePointTrieBuilder`, which a table generator runs.
##
## Bring it in with `import trie`.
##
## - `CodePointTrieBuilder`: set values for code points and ranges, `build`
##   the data, and write it with `CodePointTrieData.source` as a `const`
## - `CodePointTrie<T>`: reads a code point's value in O(1), with no
##   allocation
##
## @example
##     import trie;
##
##     main(): int {
##         var builder = trie.CodePointTrieBuilder(1);
##         builder.set_range(0x4E00, 0x9FFF, 2);
##         var widths = builder.build().reader<u8>();
##         print(widths.get(0x4E2D));   # 2
##         return 0;
##     }

# This file only gathers the module's public API from its other files.

import "code_point_trie";
import "code_point_trie_builder";
import "hat_trie";

export CodePointTrie;
export CodePointTrieBuilder;
export CodePointTrieData;
export CodePointTrieKind;
export DEFAULT_BURST_THRESHOLD;
export HatTrie;
export HatTrieIterator;
export MAX_CODE_POINT;
