## `CodePointTrie<T>`: an immutable map from Unicode code points to small
## integers, read from data that `CodePointTrieBuilder` made, after ICU's
## `UCPTrie`.

# Code points below this are read straight from the data: the builder lays
# out their values first, in order.
const _LINEAR_LIMIT: uint = 0x80;
# Code points per data block below `fast_limit` (64).
const _FAST_SHIFT: uint = 6;
const _FAST_MASK: uint = 63;
# Above `fast_limit`, an index-1 entry covers 1024 code points and points at
# an index-2 block of 64 entries, each the start of a 16-value data block.
const _INDEX1_SHIFT: uint = 10;
const _INDEX2_SHIFT: uint = 4;
const _INDEX2_MASK: uint = 63;
const _SMALL_MASK: uint = 15;

## An immutable code point trie: maps every code point, 0 to 0x10FFFF, to a
## value of type `T`, in O(1) with no allocation.
##
## The data is one `StringConstant` that a `CodePointTrieBuilder` wrote
## (`CodePointTrieData.source`), so a `const` of a trie is static data: it
## costs only its bytes in the binary, no startup work, and nothing in a
## program that never reads it. A string literal holds only bytes up to
## 0x7F as static data (pep-lang/pepper#298), so each byte carries 7 bits,
## and an entry takes one or more of them, low bits first.
##
## The layout follows ICU's `UCPTrie`:
##
## - a code point below 0x80 reads its value at data entry `cp`: one read;
## - one below `fast_limit` (0x10000, or 0x1000 for a small trie) reads the
##   start of its 64-value data block from a flat index: two reads;
## - one from `high_start` up has `high_value`: no read;
## - the rest read an index-1 entry for their 1024 code points, an index-2
##   entry for their 16, then the value: three reads.
##
## @typeParam T the value type: `u8`, `u16` or `uint`, or any integer type
##   the trie's values fit in
## @example
##     import trie;
##
##     # Written by CodePointTrieData.source(): ASCII is 1, the rest 0.
##     const ASCII = trie.CodePointTrie<u8>("...", 1, 1, 65536, 1024, 0, 1040);
##
##     main(): int {
##         print(ASCII.get('a' as uint));   # 1
##         return 0;
##     }
[Value]
export struct CodePointTrie<T> {
    ## The bytes: the index entries, then the data entries.
    var data: StringConstant;
    ## The bytes of each data entry, 1 to 5.
    var value_digits: ulong;
    ## The bytes of each index entry, 1 to 3.
    var index_digits: ulong;
    ## The code point the flat index stops at: 0x10000, or 0x1000 for a
    ## small trie.
    var fast_limit: uint;
    ## The first code point of the run at the top whose values are all
    ## `high_value`; a multiple of 1024.
    var high_start: uint;
    ## The value of every code point from `high_start` up.
    var high_value: uint;
    ## The number of index entries, before the data entries.
    var index_length: ulong;

    ## Makes a trie over data a `CodePointTrieBuilder` wrote. Pass the
    ## arguments `CodePointTrieData.source` gives; with literal arguments, a
    ## `const` of the trie is static data.
    ##
    ## @param data the bytes
    ## @param value_digits the bytes of each data entry
    ## @param index_digits the bytes of each index entry
    ## @param fast_limit where the flat index stops
    ## @param high_start where the run of `high_value` at the top starts
    ## @param high_value the value of every code point from `high_start` up
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

    ## Returns the value of `cp`. A code point past 0x10FFFF has
    ## `high_value`, as the top of the range does.
    ##
    ## @param cp the code point
    ## @returns its value
    ## @example
    ##     var width = WIDTHS.get(0x4E2D);
    get(cp: uint): T {
        if (cp < _LINEAR_LIMIT) {
            return _value(cp as ulong) as T;
        }
        if (cp < fast_limit) {
            var block = _index((cp >> _FAST_SHIFT) as ulong);
            return _value(block + (cp & _FAST_MASK) as ulong) as T;
        }
        if (cp >= high_start) {
            return high_value as T;
        }
        var index1 = ((fast_limit >> _FAST_SHIFT) + ((cp - fast_limit) >> _INDEX1_SHIFT)) as ulong;
        var index2 = _index(index1) + ((cp >> _INDEX2_SHIFT) & _INDEX2_MASK) as ulong;
        return _value(_index(index2) + (cp & _SMALL_MASK) as ulong) as T;
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
