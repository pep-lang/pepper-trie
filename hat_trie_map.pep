## `HatTrieMap<T>`: a map from `String` keys to values, kept in key order, after
## Askitis and Sinha's HAT-trie.

extern int memcmp(void* a, void* b, ulong n);

## How many keys a container holds before `HatTrieMap` bursts it into a trie
## node, unless the trie is made with another threshold.
export const DEFAULT_BURST_THRESHOLD: ulong = 16384;

# A container's average keys per bucket before its bucket count doubles,
# and the bucket count it starts with.
const _BUCKET_LOAD: ulong = 8;
const _FIRST_BUCKETS: ulong = 4;

# A node of the trie: a trie node when `children` is set, a container
# (an array hash) otherwise.
#
# A trie node has a child for each byte (null when no key continues with
# it) and the value of the key that ends at it, if one does.
#
# A container holds the rest of each key below it, past the bytes the trie
# nodes above it took. Its buckets are byte arrays of entries laid end to
# end, each the rest's size (a varint), its bytes, and the index of its value
# in `values` (a varint): no object and no pointer per key, which is where
# the memory goes in a hash map of `String`s. A removed value's slot goes on
# `free` for the next insert.
struct _HatNode<T> {
    var children: Array<_HatNode<T>>;
    var has_value: bool;
    var value: T;
    var buckets: Array<u8[]>;
    var values: Array<T>;
    var free: Array<uint>;
    var size: ulong;

    construct() {
        buckets = _empty_buckets(_FIRST_BUCKETS);
        values = Array<T>();
        free = Array<uint>();
    }

    is_trie(): bool {
        return children !== __null;
    }

    # The value index of the `size` bytes at `key`, or -1.
    find(key: __ptr<char>, size: ulong): long {
        var bucket = buckets[_bucket_of(key, size, buckets.count)];
        var at = _scan(bucket, key, size);
        if (at < 0) {
            return -1;
        }
        __ptr<u8> bytes = bucket.data();
        var (length, start) = _read_varint(bytes, at as ulong);
        var (index, end) = _read_varint(bytes, start + length);
        return index as long;
    }

    # Adds or replaces the value of the `size` bytes at `key`; true when added.
    insert(key: __ptr<char>, size: ulong, value: T): bool {
        var hash = _pep_hash_bytes(key, size);
        var bucket = buckets[(hash & (buckets.count - 1) as u64) as ulong];
        var at = _scan(bucket, key, size);
        if (at >= 0) {
            __ptr<u8> bytes = bucket.data();
            var (length, start) = _read_varint(bytes, at as ulong);
            var (found, end) = _read_varint(bytes, start + length);
            values[found] = value;
            return false;
        }
        ulong index;
        if (free.count > 0) {
            index = free.pop() as ulong;
            values[index] = value;
        } else {
            index = values.count;
            values.append(value);
        }
        if (this.size + 1 > buckets.count * _BUCKET_LOAD) {
            _rehash(buckets.count * 2);
            bucket = buckets[(hash & (buckets.count - 1) as u64) as ulong];
        }
        _write_entry(bucket, key, size, index);
        return true;
    }

    # Removes the `size` bytes at `key`; true when they were there.
    remove(key: __ptr<char>, size: ulong): bool {
        var bucket = buckets[_bucket_of(key, size, buckets.count)];
        var at = _scan(bucket, key, size);
        if (at < 0) {
            return false;
        }
        __ptr<u8> bytes = bucket.data();
        var (length, start) = _read_varint(bytes, at as ulong);
        var (index, end) = _read_varint(bytes, start + length);
        bucket.drain(at as ulong, end);
        values[index] = __default<T>();
        free.append(index as uint);
        this.size -= 1;
        return true;
    }

    # Appends an entry for a key known to be absent.
    _append(key: __ptr<char>, size: ulong, index: ulong) {
        _write_entry(buckets[_bucket_of(key, size, buckets.count)], key, size, index);
    }

    _write_entry(bucket: u8[], key: __ptr<char>, size: ulong, index: ulong) {
        _write_varint(bucket, size);
        bucket.append_from(unsafe_cast<__ptr<u8>>(key), size);
        _write_varint(bucket, index);
        this.size += 1;
    }

    _rehash(count: ulong) {
        var old = buckets;
        buckets = _empty_buckets(count);
        size = 0;
        for (var bucket in old) {
            _each(bucket, (key, length, index) => _append(key, length, index));
        }
    }

    # Turns this container into a trie node, with a chain of trie nodes for
    # the bytes all its keys start with (so a long shared prefix moves each
    # key once, not once per byte), then a container per next byte, which
    # holds the keys without the bytes above it.
    burst() {
        var shared = _shared_prefix();
        var old_buckets = buckets;
        var old_values = values;
        _become_trie();
        var node = this;
        for (var byte in shared) {
            var next = _HatNode<T>();
            next._become_trie();
            node.children[byte as ulong] = next;
            node = next;
        }
        var target = node;
        var skip = shared.count;
        for (var bucket in old_buckets) {
            _each(bucket, (key, length, index) => target._move(key + skip, length - skip, old_values[index]));
        }
    }

    _become_trie() {
        children = Array<_HatNode<T>>();
        children.resize(256, __default<_HatNode<T>>());
        buckets = __default<Array<u8[]>>();
        values = __default<Array<T>>();
        free = __default<Array<uint>>();
        size = 0;
    }

    # The bytes every key of this container starts with.
    _shared_prefix(): u8[] {
        var shared = Array<u8>();
        bool first = true;
        for (var bucket in buckets) {
            __ptr<u8> bytes = bucket.data();
            ulong at = 0;
            while (at < bucket.count) {
                var (length, start) = _read_varint(bytes, at);
                if (first) {
                    shared.append_from(bytes + start, length);
                    first = false;
                } else {
                    ulong same = 0;
                    while (same < shared.count and same < length and shared[same] == bytes[start + same]) {
                        same += 1;
                    }
                    shared.truncate(same);
                }
                var (index, end) = _read_varint(bytes, start + length);
                at = end;
            }
        }
        return shared;
    }

    # Puts a key of a burst container below this trie node.
    _move(key: __ptr<char>, length: ulong, moved: T) {
        if (length == 0) {
            has_value = true;
            value = moved;
            return;
        }
        var child = child_for(key[0] as u8);
        child.insert(key + 1, length - 1, moved);
    }

    # The child for `byte`, made as an empty container when there is none.
    child_for(byte: u8): _HatNode<T> {
        var child = children[byte as ulong];
        if (child === __null) {
            child = _HatNode<T>();
            children[byte as ulong] = child;
        }
        return child;
    }

    # This container's keys that start with the `size` bytes at `prefix`,
    # each after `path`, with their values, in key order.
    sorted(path: u8[], prefix: __ptr<char>, size: ulong): Array<(String, T)> {
        var entries = Array<(String, T)>();
        for (var bucket in buckets) {
            _each(bucket, (key, length, index) => {
                if (length >= size and (size == 0 or memcmp(key, prefix, size) == 0)) {
                    entries.append((_key_string(path, key, length), values[index]));
                }
            });
        }
        entries.sort_unstable((a, b) => a.0.compare(b.0));
        return entries;
    }
}

# `count` buckets, each an empty Array. Not null ones: storing a null Array
# in an Array stores an empty one (pep-lang/pepper#304).
_empty_buckets(count: ulong): Array<u8[]> {
    var buckets = Array<u8[]>(count);
    for (var i in 0..count) {
        buckets.append(Array<u8>());
    }
    return buckets;
}

# Calls `visit` with each entry of `bucket`: its key bytes, their size, and
# its value index.
_each(bucket: u8[], visit: (__ptr<char>, ulong, ulong) => void) {
    __ptr<u8> bytes = bucket.data();
    ulong at = 0;
    while (at < bucket.count) {
        var (length, start) = _read_varint(bytes, at);
        var (index, end) = _read_varint(bytes, start + length);
        visit(unsafe_cast<__ptr<char>>(bytes + start), length, index);
        at = end;
    }
}

# The offset of the entry for the `size` bytes at `key` in `bucket`, or -1.
_scan(bucket: u8[], key: __ptr<char>, size: ulong): long {
    __ptr<u8> bytes = bucket.data();
    ulong at = 0;
    while (at < bucket.count) {
        var (length, start) = _read_varint(bytes, at);
        if (length == size and (size == 0 or memcmp(bytes + start, key, size) == 0)) {
            return at as long;
        }
        at = start + length;
        # Skip the value index's varint.
        while (bytes[at] >= 0x80) {
            at += 1;
        }
        at += 1;
    }
    return -1;
}

_bucket_of(key: __ptr<char>, size: ulong, count: ulong): ulong {
    return (_pep_hash_bytes(key, size) & (count - 1) as u64) as ulong;
}

# The varint at `at`, and the offset after it.
_read_varint(bytes: __ptr<u8>, at: ulong): (ulong, ulong) {
    ulong value = 0;
    uint shift = 0;
    while (bytes[at] >= 0x80) {
        value = value | (((bytes[at] & 0x7F) as ulong) << shift);
        shift += 7;
        at += 1;
    }
    return (value | ((bytes[at] as ulong) << shift), at + 1);
}

_write_varint(bytes: u8[], value: ulong) {
    while (value >= 0x80) {
        bytes.append(((value & 0x7F) | 0x80) as u8);
        value = value >> 7;
    }
    bytes.append(value as u8);
}

# `path` then the `size` bytes at `rest`, as a String.
_key_string(path: u8[], rest: __ptr<char>, size: ulong): String {
    if (path.count + size == 0) {
        return String();
    }
    var bytes = Array<u8>(path.count + size);
    bytes.append_all(path);
    if (size > 0) {
        bytes.append_from(unsafe_cast<__ptr<u8>>(rest), size);
    }
    return String(unsafe_cast<__ptr<char>>(bytes.data()), bytes.count);
}

## A map from `String` keys to values of type `T` that keeps its keys in
## byte order (code point order, for valid UTF-8), after the HAT-trie of
## Askitis and Sinha: a trie whose leaves are array hash tables
## ("containers") that hold the rest of each key below them.
##
## A container packs its keys into a few byte arrays, with no object per
## key, so the map takes much less memory than a `HashMap<String, T>` of the
## same keys. When a container holds more than the burst threshold of keys,
## it bursts: it becomes a trie node, and its keys move to a new container
## per first byte, without that byte. Lookups hash in one container after
## walking the trie, so they cost about as much as a hash map's; iterating
## in order sorts each container as it reaches it, and a prefix search
## (`with_prefix`) walks to the prefix and visits only what is under it.
##
## Keys are compared as bytes. The map holds a reference to each value; it
## does not keep the key objects, only their bytes, so a key given to
## `insert` may be changed afterwards.
##
## @typeParam T the value type
## @example
##     import trie;
##
##     main(): int {
##         var words = trie.HatTrieMap<int>();
##         words["pepper"] = 1;
##         words["pear"] = 2;
##         words["apple"] = 3;
##         for (var (word, n) in words.with_prefix("pe")) {
##             print($"{word} {n}");   # pear 2, then pepper 1
##         }
##         return 0;
##     }
export struct HatTrieMap<T> {
    var _root: _HatNode<T>;
    var _count: ulong;
    var _burst_threshold: ulong;
    # Changed by every insert of a new key and every removal, so an
    # iterator can tell that its trie changed.
    var _version: ulong;

    ## Makes an empty trie.
    ##
    ## A lower `burst_threshold` makes more, smaller containers: in-order
    ## and prefix iteration sort less at a time, at the cost of more trie
    ## nodes (2 KB each). Tessil's hat-trie suggests 1024 or less when
    ## iteration matters more than lookups.
    ##
    ## @param burst_threshold how many keys a container holds before it
    ##   bursts; at least 4
    ## @panics if `burst_threshold` is below 4
    construct(burst_threshold: ulong = DEFAULT_BURST_THRESHOLD) {
        assert(burst_threshold >= 4, "HatTrieMap: the burst threshold must be at least 4");
        _root = _HatNode<T>();
        _burst_threshold = burst_threshold;
    }

    ## The number of keys.
    var count: ulong {
        get {
            return _count;
        }
    }

    ## Whether the trie has no keys.
    var is_empty: bool {
        get {
            return _count == 0;
        }
    }

    ## Adds `key` with `value`, or replaces the value of `key` when it is
    ## already there.
    ##
    ## @param key the key; its bytes are copied
    ## @param value the value to store for `key`
    ## @returns true when `key` was added, false when its value was replaced
    insert(key: String, value: T): bool {
        __ptr<char> bytes = key.c_str();
        var node = _root;
        ulong depth = 0;
        while (node.is_trie()) {
            if (depth == key.size) {
                var added = !node.has_value;
                node.has_value = true;
                node.value = value;
                _added(added);
                return added;
            }
            node = node.child_for(bytes[depth] as u8);
            depth += 1;
        }
        var added = node.insert(bytes + depth, key.size - depth, value);
        if (node.size > _burst_threshold) {
            node.burst();
        }
        _added(added);
        return added;
    }

    _added(added: bool) {
        if (added) {
            _count += 1;
            _version += 1;
        }
    }

    ## Returns the value of `key`, or the default of `T` (0, or a null
    ## reference) when it is not there.
    ##
    ## @param key the key to look up
    ## @returns the value, or the default of `T`
    get(key: String): T {
        if (try_get(key) is Value(found)) {
            return found;
        }
        return __default<T>();
    }

    ## Returns the value of `key`, or none when it is not there.
    ##
    ## @param key the key to look up
    ## @returns the value, or none
    try_get(key: String): T? {
        __ptr<char> bytes = key.c_str();
        var node = _root;
        ulong depth = 0;
        while (node.is_trie()) {
            if (depth == key.size) {
                if (node.has_value) {
                    return Optional<T>.Value(node.value);
                }
                return Optional<T>.Empty;
            }
            node = node.children[(bytes[depth] as u8) as ulong];
            if (node === __null) {
                return Optional<T>.Empty;
            }
            depth += 1;
        }
        var index = node.find(bytes + depth, key.size - depth);
        if (index < 0) {
            return Optional<T>.Empty;
        }
        return Optional<T>.Value(node.values[index as ulong]);
    }

    ## Whether `key` is in the trie.
    ##
    ## @param key the key to look for
    ## @returns true when it is there
    contains(key: String): bool {
        return try_get(key).is_value();
    }

    ## Reads `trie[key]`: the same as `get`.
    ##
    ## @param key the key to look up
    ## @returns the value, or the default of `T`
    [](key: String): T {
        return get(key);
    }

    ## Writes `trie[key] = value`: the same as `insert`.
    ##
    ## @param key the key
    ## @param value the value to store for it
    ## @returns `value`
    [](key: String, value: T): T {
        insert(key, value);
        return value;
    }

    ## Removes `key` and releases its value. Trie nodes stay when their keys
    ## go; only `clear` gives their memory back.
    ##
    ## @param key the key to remove
    ## @returns true when `key` was there
    remove(key: String): bool {
        __ptr<char> bytes = key.c_str();
        var node = _root;
        ulong depth = 0;
        while (node.is_trie()) {
            if (depth == key.size) {
                if (!node.has_value) {
                    return false;
                }
                node.has_value = false;
                node.value = __default<T>();
                _removed();
                return true;
            }
            node = node.children[(bytes[depth] as u8) as ulong];
            if (node === __null) {
                return false;
            }
            depth += 1;
        }
        if (node.remove(bytes + depth, key.size - depth)) {
            _removed();
            return true;
        }
        return false;
    }

    _removed() {
        _count -= 1;
        _version += 1;
    }

    ## Removes every key.
    clear() {
        _root = _HatNode<T>();
        _count = 0;
        _version += 1;
    }

    ## Returns an iterator over the entries as `(key, value)` tuples, in key
    ## order; `for (var (key, value) in trie)` drives it.
    ##
    ## Each container is sorted when the iterator reaches it, which costs
    ## O(n log n) for its n keys. Adding or removing a key makes the
    ## iterator's next `next()` panic.
    ##
    ## @returns an iterator positioned before the first entry
    iterate(): HatTrieMapIterator<T> {
        return HatTrieMapIterator<T>(this, _root, Array<u8>(), "", 0);
    }

    ## Returns an iterator over the entries whose key starts with `prefix`,
    ## in key order. It walks the trie to `prefix`, so it visits only the
    ## keys under it, plus the rest of one container when `prefix` ends
    ## inside one.
    ##
    ## @param prefix the bytes every key visited starts with; `""` visits all
    ## @returns an iterator positioned before the first such entry
    ## @example
    ##     var n = 0;
    ##     for (var (key, value) in trie.with_prefix("app")) {
    ##         n += 1;
    ##     }
    with_prefix(prefix: String): HatTrieMapIterator<T> {
        __ptr<char> bytes = prefix.c_str();
        var node = _root;
        var path = Array<u8>();
        ulong depth = 0;
        while (node.is_trie() and depth < prefix.size) {
            node = node.children[(bytes[depth] as u8) as ulong];
            if (node === __null) {
                return HatTrieMapIterator<T>(this, __default<_HatNode<T>>(), path, "", 0);
            }
            path.append(bytes[depth] as u8);
            depth += 1;
        }
        return HatTrieMapIterator<T>(this, node, path, prefix, depth);
    }
}

## An `Iterator<(String, T)>` over a `HatTrieMap`'s entries in key order;
## returned by `HatTrieMap.iterate` and `HatTrieMap.with_prefix`.
##
## It holds a reference to the trie and fails fast: adding or removing a key
## after it was made makes its next `next()` or `current()` panic.
##
## @typeParam T the trie's value type
export struct HatTrieMapIterator<T> {
    var _trie: HatTrieMap<T>;
    var _version: ulong;
    # The trie nodes from the start down to the current one, and the next
    # byte to try at each.
    var _nodes: Array<_HatNode<T>>;
    var _next: Array<uint>;
    # The bytes to the current trie node.
    var _path: u8[];
    # The entries of the current node or container, sorted, and which of
    # them is current.
    var _entries: Array<(String, T)>;
    var _at: ulong;
    var _started: bool;

    ## Makes an iterator over the keys under `start`, which `path` leads to,
    ## that start with `prefix`'s bytes from `depth` on. `HatTrieMap.iterate`
    ## and `HatTrieMap.with_prefix` call it.
    ##
    ## @param trie the trie
    ## @param start the node to start at; null for no entries
    ## @param path the bytes that lead to `start`
    ## @param prefix the prefix searched for
    ## @param depth how many of `prefix`'s bytes `path` holds
    construct(trie: HatTrieMap<T>, start: _HatNode<T>, path: u8[], prefix: String, depth: ulong) {
        _trie = trie;
        _version = trie._version;
        _nodes = Array<_HatNode<T>>();
        _next = Array<uint>();
        _path = path;
        _entries = Array<(String, T)>();
        if (start === __null) {
            # Nothing has the prefix.
        } else if (start.is_trie()) {
            _push(start);
        } else {
            _entries = start.sorted(path, prefix.c_str() + depth, prefix.size - depth);
        }
    }

    ## Advances to the next entry.
    ##
    ## @returns true when there is a current entry, false once every entry
    ##   was visited
    ## @panics if a key was added or removed since the iterator was made
    ##   ("HatTrieMap modified during iteration")
    next(): bool {
        assert(_trie._version == _version, "HatTrieMap modified during iteration");
        if (_started) {
            _at += 1;
        }
        _started = true;
        while (_at >= _entries.count) {
            if (_nodes.count == 0) {
                return false;
            }
            _entries = Array<(String, T)>();
            _at = 0;
            _advance();
        }
        return true;
    }

    ## Returns the entry the last successful `next()` moved to.
    ##
    ## @returns the current entry as a `(key, value)` tuple
    ## @panics if a key was added or removed since the iterator was made
    ##   ("HatTrieMap modified during iteration")
    ## @panics if `next()` was not called or returned false
    ##   ("HatTrieMapIterator.current() without an entry")
    current(): (String, T) {
        assert(_trie._version == _version, "HatTrieMap modified during iteration");
        assert(_started and _at < _entries.count, "HatTrieMapIterator.current() without an entry");
        return _entries[_at];
    }

    # Enters trie node `node`, whose path `_path` holds: its own key first.
    _push(node: _HatNode<T>) {
        _nodes.append(node);
        _next.append(0);
        if (node.has_value) {
            _entries.append((_key_string(_path, __null, 0), node.value));
        }
    }

    # Moves to the next child of the deepest trie node, or up past it.
    _advance() {
        var top = _nodes.count - 1;
        var node = _nodes[top];
        var byte = _next[top];
        while (byte < 256 and node.children[byte as ulong] === __null) {
            byte += 1;
        }
        if (byte == 256) {
            _nodes.pop();
            _next.pop();
            if (_nodes.count > 0) {
                _path.pop();
            }
            return;
        }
        _next[top] = byte + 1;
        var child = node.children[byte as ulong];
        _path.append(byte as u8);
        if (child.is_trie()) {
            _push(child);
        } else {
            _entries = child.sorted(_path, __null, 0);
            _path.pop();
        }
    }
}
