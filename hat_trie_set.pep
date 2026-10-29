## `HatTrieSet`: a set of `String`s kept in order, a `HatTrieMap` with no
## values.

import "hat_trie_map";

## A set of `String`s that keeps them in byte order (code point order, for
## valid UTF-8): a `HatTrieMap` whose values take no room, as Tessil's
## `htrie_set` is to `htrie_map`. It packs the strings into the containers'
## byte arrays, with no object per string, so it takes much less memory than
## a `HashSet<String>`, and finds every string with a prefix by walking to
## it (`with_prefix`).
##
## @example
##     import trie;
##
##     main(): int {
##         var words = trie.HatTrieSet();
##         words.insert("pepper");
##         words.insert("pear");
##         words.insert("apple");
##         for (var word in words.with_prefix("pe")) {
##             print(word);   # pear, then pepper
##         }
##         return 0;
##     }
export struct HatTrieSet {
    var _map: HatTrieMap<_NoValue>;

    ## Makes an empty set.
    ##
    ## @param burst_threshold how many strings a container holds before it
    ##   bursts; at least 4 (see `HatTrieMap`)
    ## @panics if `burst_threshold` is below 4
    construct(burst_threshold: ulong = DEFAULT_BURST_THRESHOLD) {
        _map = HatTrieMap<_NoValue>(burst_threshold);
    }

    ## The number of strings.
    var count: ulong {
        get {
            return _map.count;
        }
    }

    ## Whether the set has no strings.
    var is_empty: bool {
        get {
            return _map.is_empty;
        }
    }

    ## Adds `key` when it is not there yet.
    ##
    ## @param key the string; its bytes are copied
    ## @returns true when `key` was added, false when it was there already
    insert(key: String): bool {
        return _map.insert(key, _NoValue());
    }

    ## Whether `key` is in the set.
    ##
    ## @param key the string to look for
    ## @returns true when it is there
    contains(key: String): bool {
        return _map.contains(key);
    }

    ## Removes `key`.
    ##
    ## @param key the string to remove
    ## @returns true when `key` was there
    remove(key: String): bool {
        return _map.remove(key);
    }

    ## Removes every string.
    clear() {
        _map.clear();
    }

    ## Returns an iterator over the strings in order; `for (var key in set)`
    ## drives it. Adding or removing a string makes its next `next()` panic.
    ##
    ## @returns an iterator positioned before the first string
    iterate(): HatTrieSetIterator {
        return HatTrieSetIterator(_map.iterate());
    }

    ## Returns an iterator over the strings that start with `prefix`, in
    ## order, visiting only what is under `prefix` (see
    ## `HatTrieMap.with_prefix`).
    ##
    ## @param prefix the bytes every string visited starts with; `""` visits all
    ## @returns an iterator positioned before the first such string
    with_prefix(prefix: String): HatTrieSetIterator {
        return HatTrieSetIterator(_map.with_prefix(prefix));
    }
}

## An `Iterator<String>` over a `HatTrieSet`'s strings in order; returned by
## `HatTrieSet.iterate` and `HatTrieSet.with_prefix`. It fails fast as
## `HatTrieMapIterator` does.
export struct HatTrieSetIterator {
    var _entries: HatTrieMapIterator<_NoValue>;

    ## Makes an iterator over the keys `entries` visits. `HatTrieSet` calls it.
    ##
    ## @param entries the iterator over the set's map
    construct(entries: HatTrieMapIterator<_NoValue>) {
        _entries = entries;
    }

    ## Advances to the next string.
    ##
    ## @returns true when there is a current string, false once every one was
    ##   visited
    ## @panics if a string was added or removed since the iterator was made
    next(): bool {
        return _entries.next();
    }

    ## Returns the string the last successful `next()` moved to.
    ##
    ## @returns the current string
    ## @panics if `next()` was not called or returned false, or the set changed
    current(): String {
        return _entries.current().0;
    }
}
