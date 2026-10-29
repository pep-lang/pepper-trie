## `CodePointTrieBuilder`: builds a `CodePointTrie` from code point ranges
## and their values, at generation time, and writes it as Pepper source.

import "code_point_trie";

## The largest code point.
export const MAX_CODE_POINT: uint = 0x10FFFF;

# The bits each byte of the data carries (pep-lang/pepper#298).
const _DIGIT_BITS: uint = 7;
const _HEX = "0123456789ABCDEF";

## Which layout `CodePointTrieBuilder.build` writes, as ICU's
## `UCPTRIE_TYPE_FAST` and `UCPTRIE_TYPE_SMALL`.
export enum CodePointTrieKind {
    ## A flat index for the whole BMP: two reads below U+10000, and a larger
    ## index (1024 entries).
    Fast,
    ## A flat index only below U+1000: two reads there, three above, and a
    ## smaller index.
    Small,
}

## Builds a `CodePointTrie`: set values for code points and ranges, then
## `build` it.
##
## Holds a value for each of the 0x110000 code points (4.4 MB), so it is for
## generators, not for programs that read the trie. `build` merges equal
## data blocks and equal index blocks, and overlaps each new block with the
## end of the one before where they agree, as ICU's builder does.
##
## @example
##     import trie;
##
##     var builder = trie.CodePointTrieBuilder(1);
##     builder.set_range(0x1100, 0x115F, 2);
##     builder.set(0x200B, 0);
##     var data = builder.build();
##     var widths = data.reader<u8>();      # widths.get(0x1100) == 2
##     print(data.source("u8"));             # trie.CodePointTrie<u8>("...", ...)
export struct CodePointTrieBuilder {
    var _values: uint[];

    ## Makes a builder in which every code point has `initial_value`.
    ##
    ## @param initial_value the value of every code point until one is set
    construct(initial_value: uint = 0) {
        _values = Array<uint>();
        _values.resize((MAX_CODE_POINT + 1) as ulong, initial_value);
    }

    ## Returns the value set for `cp` so far.
    ##
    ## @param cp the code point
    ## @returns its value
    ## @panics if `cp` is past 0x10FFFF
    get(cp: uint): uint {
        assert(cp <= MAX_CODE_POINT, "CodePointTrieBuilder: code point past 0x10FFFF");
        return _values[cp as ulong];
    }

    ## Sets the value of `cp`.
    ##
    ## @param cp the code point
    ## @param value its value
    ## @panics if `cp` is past 0x10FFFF
    set(cp: uint, value: uint) {
        assert(cp <= MAX_CODE_POINT, "CodePointTrieBuilder: code point past 0x10FFFF");
        _values[cp as ulong] = value;
    }

    ## Sets the value of every code point from `first` to `last`, both
    ## included.
    ##
    ## @param first the first code point of the range
    ## @param last the last code point of the range
    ## @param value their value
    ## @panics if `last` is past 0x10FFFF or `first` is past `last`
    set_range(first: uint, last: uint, value: uint) {
        assert(last <= MAX_CODE_POINT, "CodePointTrieBuilder: code point past 0x10FFFF");
        assert(first <= last, "CodePointTrieBuilder: range ends before it starts");
        for (var cp in first as ulong..last as ulong + 1) {
            _values[cp] = value;
        }
    }

    ## Builds the trie's data. The builder is unchanged, so it can be built
    ## again after more changes.
    ##
    ## @param kind the layout: `Fast` (the default) or `Small`
    ## @returns the data, which `CodePointTrieData.source` writes as Pepper
    ##   source and `CodePointTrieData.reader` reads
    build(kind: CodePointTrieKind = CodePointTrieKind.Fast): CodePointTrieData {
        uint fast_limit = kind == CodePointTrieKind.Fast ? 0x10000 : 0x1000;
        var high_value = _values[MAX_CODE_POINT as ulong];
        ulong last = MAX_CODE_POINT as ulong;
        while (last > 0 and _values[last] == high_value) {
            last -= 1;
        }
        var high_start = ((last + 1 + 1023) / 1024 * 1024) as uint;
        if (high_start < fast_limit) {
            high_start = fast_limit;
        }

        var data = _Blocks();
        # ASCII first and in order, so the reader finds it at data entry `cp`.
        for (var cp in 0..128) {
            data.entries.append(_values[cp]);
        }
        data.remember(_values, 0, 0, 64);
        data.remember(_values, 64, 64, 64);

        var index = Array<ulong>();
        for (var block in 0..(fast_limit / 64) as ulong) {
            index.append(data.place(_values, block * 64, 64));
        }
        var index1_count = ((high_start - fast_limit) / 1024) as ulong;
        var index2_start = index.count + index1_count;
        var index2 = _Blocks();
        var index1 = Array<ulong>();
        for (var chunk in 0..index1_count) {
            var first = fast_limit as ulong + chunk * 1024;
            var entries = Array<uint>();
            for (var block in 0..64) {
                entries.append(data.place(_values, first + block * 16, 16) as uint);
            }
            index1.append(index2_start + index2.place(entries, 0, 64));
        }
        index.append_all(index1);
        for (var entry in index2.entries) {
            index.append(entry as ulong);
        }

        ulong max_index = 0;
        for (var entry in index) {
            max_index = entry > max_index ? entry : max_index;
        }
        uint max_value = 0;
        for (var entry in data.entries) {
            max_value = entry > max_value ? entry : max_value;
        }
        var result = CodePointTrieData();
        result.value_digits = _digits(max_value as ulong);
        result.index_digits = _digits(max_index);
        result.fast_limit = fast_limit;
        result.high_start = high_start;
        result.high_value = high_value;
        result.index_length = index.count;
        var bytes = Array<u8>();
        for (var entry in index) {
            _put(bytes, entry, result.index_digits);
        }
        for (var entry in data.entries) {
            _put(bytes, entry as ulong, result.value_digits);
        }
        result.bytes = bytes;
        return result;
    }
}

## The data `CodePointTrieBuilder.build` made: the bytes and the parameters
## a `CodePointTrie` reads them with.
export struct CodePointTrieData {
    ## The bytes, each 0 to 0x7F: the index entries, then the data entries.
    var bytes: u8[];
    ## The bytes of each data entry.
    var value_digits: ulong;
    ## The bytes of each index entry.
    var index_digits: ulong;
    ## The code point the flat index stops at.
    var fast_limit: uint;
    ## Where the run of `high_value` at the top starts.
    var high_start: uint;
    ## The value of every code point from `high_start` up.
    var high_value: uint;
    ## The number of index entries.
    var index_length: ulong;
    # The bytes as text, which `reader` points into.
    var _text: String;

    ## Makes empty data; `CodePointTrieBuilder.build` fills it in.
    construct() {
        bytes = Array<u8>();
    }

    ## Returns a trie that reads these bytes at run time, for data built in
    ## the same program (a test, or a table built at startup). It points into
    ## this object, which must outlive it and not change. A generator
    ## writes `source()` instead, which needs no such care.
    ##
    ## @typeParam T the value type; every value must fit in it
    ## @returns the trie
    reader<T>(): CodePointTrie<T> {
        _text = String(unsafe_cast<__ptr<char>>(bytes.data()), bytes.count);
        return CodePointTrie<T>(
            StringConstant(_text.c_str(), _text.size, _text.length),
            value_digits,
            index_digits,
            fast_limit,
            high_start,
            high_value,
            index_length
        );
    }

    ## Returns the Pepper expression that makes this trie from literals, for
    ## a generator to write after `const NAME = `; the program that reads it
    ## then holds the bytes as static data. It names the type as
    ## `trie.CodePointTrie`, so that file imports `trie`.
    ##
    ## The string is one line. Bytes from space to `~` are written as they
    ## are (with `"` and `\` escaped), the rest as `\x` escapes.
    ##
    ## @param value_type the trie's value type, such as `"u8"`
    ## @returns the expression
    ## @example
    ##     var line = $"const _WIDTH = {data.source("u8")};";
    source(value_type: String): String {
        var text = Array<u8>();
        for (var b in bytes) {
            if (b == '"' as u8 or b == '\\' as u8) {
                text.append('\\' as u8);
                text.append(b);
            } else if (b >= 0x20 and b < 0x7F) {
                text.append(b);
            } else {
                text.append('\\' as u8);
                text.append('x' as u8);
                text.append(_HEX.byte_at((b >> 4) as ulong) as u8);
                text.append(_HEX.byte_at((b & 15) as ulong) as u8);
            }
        }
        var literal = text.count == 0 ? "" : String(unsafe_cast<__ptr<char>>(text.data()), text.count);
        var arguments = $"{value_digits}, {index_digits}, {fast_limit}, {high_start}, {high_value}, {index_length}";
        return $"trie.CodePointTrie<{value_type}>(\"{literal}\", {arguments})";
    }
}

# A growing array of entries that places blocks of them, reusing an equal
# block already placed and overlapping a new one with the array's end.
struct _Blocks {
    var entries: uint[];
    # Each placed block's text (`_key`), and where it starts.
    var _starts: HashMap<String, ulong>;

    construct() {
        entries = Array<uint>();
        _starts = HashMap<String, ulong>();
    }

    # Where `size` entries of `source` from `first` start in `entries`,
    # placing them if no equal block was placed.
    place(source: uint[], first: ulong, size: ulong): ulong {
        var key = _key(source, first, size);
        if (_starts.try_get(key) is Value(start)) {
            return start;
        }
        var overlap = size - 1;
        while (overlap > 0 and !_tail_matches(source, first, overlap)) {
            overlap -= 1;
        }
        var start = entries.count - overlap;
        for (var i in overlap..size) {
            entries.append(source[first + i]);
        }
        remember(source, first, start, size);
        return start;
    }

    # Records that `size` entries of `source` from `first` sit at `start`,
    # and each 16-entry block in them.
    remember(source: uint[], first: ulong, start: ulong, size: ulong) {
        _starts[_key(source, first, size)] = start;
        if (size > 16) {
            for (var part in 0..size / 16) {
                var key = _key(source, first + part * 16, 16);
                if (!_starts.contains(key)) {
                    _starts[key] = start + part * 16;
                }
            }
        }
    }

    # Whether the last `count` entries equal the `count` of `source` from `first`.
    _tail_matches(source: uint[], first: ulong, count: ulong): bool {
        if (count > entries.count) {
            return false;
        }
        var at = entries.count - count;
        for (var i in 0..count) {
            if (entries[at + i] != source[first + i]) {
                return false;
            }
        }
        return true;
    }

    _key(source: uint[], first: ulong, size: ulong): String {
        var out = StringBuilder();
        out.append(to_string(size)).append(":");
        for (var i in 0..size) {
            out.append(to_string(source[first + i])).append(",");
        }
        return out.to_string();
    }
}

# The 7-bit bytes `value` takes, at least 1.
_digits(value: ulong): ulong {
    ulong digits = 1;
    while (value >> (_DIGIT_BITS * digits as uint) != 0) {
        digits += 1;
    }
    return digits;
}

# Appends `value` as `digits` 7-bit bytes, low bits first.
_put(bytes: u8[], value: ulong, digits: ulong) {
    for (var i in 0..digits) {
        bytes.append(((value >> (_DIGIT_BITS * i as uint)) & 0x7F) as u8);
    }
}
