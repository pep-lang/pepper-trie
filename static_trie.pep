## `StaticTrie<T>`: an immutable map from integer keys, 0 to `MAX_KEY`, to
## small integers, read from data that `StaticTrieBuilder` made. It is laid
## out as ICU's `UCPTrie` is, for Unicode code points, the use it is made
## for.

## The largest key a `StaticTrie` holds: 0x10FFFF, the largest Unicode code
## point.
export const MAX_KEY: uint = 0x10FFFF;

# Keys below this are read straight from the data: the builder lays out
# their values first, in order.
const _LINEAR_LIMIT: uint = 0x80;
# Keys per data block below `fast_limit` (64).
const _FAST_SHIFT: uint = 6;
const _FAST_MASK: uint = 63;
# Above `fast_limit`, an index-1 entry covers 1024 keys and points at an
# index-2 block of 64 entries, each the start of a 16-value data block.
const _INDEX1_SHIFT: uint = 10;
const _INDEX2_SHIFT: uint = 4;
const _INDEX2_MASK: uint = 63;
const _SMALL_MASK: uint = 15;

## An immutable trie that maps every key from 0 to `MAX_KEY` to a value of
## type `T`, in O(1) with no allocation. Made for dense keys whose values
## come in runs and repeat, such as the properties of Unicode code points.
##
## Its data is one `StringConstant` that a `StaticTrieBuilder` wrote
## (`StaticTrieData.source`), so a `const` of a trie is static data: it
## costs only its bytes in the binary, no startup work, and nothing in a
## program that never reads it. A string literal holds only bytes up to
## 0x7F as static data (pep-lang/pepper#298), so each byte carries 7 bits,
## and an entry takes one or more of them, low bits first.
##
## The layout follows ICU's `UCPTrie`:
##
## - a key below 0x80 (ASCII) reads its value at data entry `key`: one read;
## - one below `fast_limit` (0x10000, the BMP, or 0x1000 for a small trie)
##   reads the start of its 64-value data block from a flat index: two
##   reads;
## - one from `high_start` up has `high_value`: no read;
## - the rest read an index-1 entry for their 1024 keys, an index-2 entry
##   for their 16, then the value: three reads.
##
## @typeParam T the value type: `u8`, `u16` or `uint`, or any integer type
##   the trie's values fit in
## @example
##     import trie;
##
##     # Written by StaticTrieData.source(), usually in a build script.
##     const WIDTHS = trie.StaticTrie<u8>("...", 1, 2, 4096, 918528, 1, 1172);
##
##     main(): int {
##         print(WIDTHS.get(0x4E2D));   # 2
##         return 0;
##     }
[Value]
export struct StaticTrie<T> {
    ## The bytes: the index entries, then the data entries.
    var data: StringConstant;
    ## The bytes of each data entry, 1 to 5.
    var value_digits: ulong;
    ## The bytes of each index entry, 1 to 3.
    var index_digits: ulong;
    ## The key the flat index stops at: 0x10000, or 0x1000 for a small trie.
    var fast_limit: uint;
    ## The first key of the run at the top whose values are all
    ## `high_value`; a multiple of 1024.
    var high_start: uint;
    ## The value of every key from `high_start` up.
    var high_value: uint;
    ## The number of index entries, before the data entries.
    var index_length: ulong;

    ## Makes a trie over data a `StaticTrieBuilder` wrote. Pass the
    ## arguments `StaticTrieData.source` gives; with literal arguments, a
    ## `const` of the trie is static data.
    ##
    ## @param data the bytes
    ## @param value_digits the bytes of each data entry
    ## @param index_digits the bytes of each index entry
    ## @param fast_limit where the flat index stops
    ## @param high_start where the run of `high_value` at the top starts
    ## @param high_value the value of every key from `high_start` up
    ## @param index_length the number of index entries
    construct(
        data: StringConstant,
        value_digits: ulong,
        index_digits: ulong,
        fast_limit: uint,
        high_start: uint,
        high_value: uint,
        index_length: ulong
    ) {
        this.data = data;
        this.value_digits = value_digits;
        this.index_digits = index_digits;
        this.fast_limit = fast_limit;
        this.high_start = high_start;
        this.high_value = high_value;
        this.index_length = index_length;
    }

    ## Returns the value of `key`. A key past `MAX_KEY` has `high_value`, as
    ## the top of the range does.
    ##
    ## @param key the key, such as a code point
    ## @returns its value
    ## @example
    ##     var width = WIDTHS.get(0x4E2D);
    get(key: uint): T {
        if (key < _LINEAR_LIMIT) {
            return _value(key as ulong) as T;
        }
        if (key < fast_limit) {
            var block = _index((key >> _FAST_SHIFT) as ulong);
            return _value(block + (key & _FAST_MASK) as ulong) as T;
        }
        if (key >= high_start) {
            return high_value as T;
        }
        var index1 = ((fast_limit >> _FAST_SHIFT) + ((key - fast_limit) >> _INDEX1_SHIFT)) as ulong;
        var index2 = _index(index1) + ((key >> _INDEX2_SHIFT) & _INDEX2_MASK) as ulong;
        return _value(_index(index2) + (key & _SMALL_MASK) as ulong) as T;
    }

    # Index entry `at`.
    _index(at: ulong): ulong {
        return _read(at * index_digits, index_digits) as ulong;
    }

    # Data entry `at`.
    _value(at: ulong): uint {
        return _read(index_length * index_digits + at * value_digits, value_digits);
    }

    # The `digits`-byte number at byte `at`, 7 bits a byte, low bits first.
    _read(at: ulong, digits: ulong): uint {
        __ptr<char> bytes = data.c_str();
        var value = bytes[at] as uint;
        if (digits > 1) {
            value = value | ((bytes[at + 1] as uint) << 7);
            for (var i in 2..digits) {
                value = value | ((bytes[at + i] as uint) << (7 * i) as uint);
            }
        }
        return value;
    }
}
