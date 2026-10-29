# CodePointTrie and its builder: every code point read back as set.

import random;
import trie;

# Every code point of `trie` reads what `builder` holds.
_expect_all(builder: trie.CodePointTrieBuilder, kind: trie.CodePointTrieKind) {
    var data = builder.build(kind);
    var reader = data.reader<uint>();
    ulong wrong = 0;
    for (var cp in 0..(trie.MAX_CODE_POINT + 1) as ulong) {
        if (reader.get(cp as uint) != builder.get(cp as uint)) {
            wrong += 1;
        }
    }
    expect_equal(wrong, 0 as ulong);
}

_expect_both(builder: trie.CodePointTrieBuilder) {
    _expect_all(builder, trie.CodePointTrieKind.Fast);
    _expect_all(builder, trie.CodePointTrieKind.Small);
}

[Test]
an_empty_builder_reads_its_initial_value() {
    var builder = trie.CodePointTrieBuilder(7);
    _expect_both(builder);
    var data = builder.build();
    expect_equal(data.reader<u8>().get(0x10FFFF), 7 as u8);
    expect_equal(data.reader<u8>().get(0x110000), 7 as u8);
    expect_equal(data.high_start, 0x10000 as uint);
}

[Test]
a_single_range_round_trips() {
    var builder = trie.CodePointTrieBuilder();
    builder.set_range(0x4E00, 0x9FFF, 2);
    _expect_both(builder);
    var reader = builder.build().reader<u8>();
    expect_equal(reader.get(0x4DFF), 0 as u8);
    expect_equal(reader.get(0x4E00), 2 as u8);
    expect_equal(reader.get(0x9FFF), 2 as u8);
    expect_equal(reader.get(0xA000), 0 as u8);
}

[Test]
edges_read_back() {
    var builder = trie.CodePointTrieBuilder(1);
    builder.set(0, 9);
    builder.set(0x7F, 10);
    builder.set(0x80, 11);
    builder.set(0xFFF, 12);
    builder.set(0x1000, 13);
    builder.set(0xFFFF, 14);
    builder.set(0x10000, 15);
    builder.set(trie.MAX_CODE_POINT, 16);
    # Surrogates are code points too: the trie keeps their values.
    builder.set_range(0xD800, 0xDFFF, 17);
    _expect_both(builder);
    var reader = builder.build(trie.CodePointTrieKind.Small).reader<ushort>();
    expect_equal(reader.get(0xDBFF), 17 as ushort);
    expect_equal(reader.get(trie.MAX_CODE_POINT), 16 as ushort);
    expect_equal(reader.get(trie.MAX_CODE_POINT - 1), 1 as ushort);
}

[Test]
value_widths_round_trip() {
    var builder = trie.CodePointTrieBuilder();
    builder.set(0x41, 0xFF);
    builder.set(0x3000, 0xFFFF);
    builder.set(0x20000, 0xFFFFFFFF);
    var data = builder.build();
    expect_equal(data.value_digits, 5 as ulong);
    expect_equal(data.reader<u8>().get(0x41), 0xFF as u8);
    expect_equal(data.reader<ushort>().get(0x3000), 0xFFFF as ushort);
    expect_equal(data.reader<uint>().get(0x20000), 0xFFFFFFFF as uint);
    _expect_both(builder);
}

[Test]
random_ranges_match_the_builder() {
    var generator = random.Generator(42);
    for (var round in 0..4) {
        var builder = trie.CodePointTrieBuilder();
        for (var i in 0..300) {
            # Mostly short runs in the BMP, some anywhere, as Unicode data is.
            var span = generator.next_int(0..(i % 3 == 0 ? 0x10FFFF : 0x10000));
            var first = span as uint;
            var last = first + generator.next_int(0..200) as uint;
            if (last > trie.MAX_CODE_POINT) {
                last = trie.MAX_CODE_POINT;
            }
            builder.set_range(first, last, generator.next_int(0..(round == 3 ? 1000000 : 40)) as uint);
        }
        _expect_both(builder);
    }
}

[Test]
equal_blocks_are_stored_once() {
    var builder = trie.CodePointTrieBuilder();
    # The same pattern in every 64-code-point block of the BMP.
    for (var cp in 0..0x10000) {
        builder.set(cp as uint, (cp % 64 == 5) ? 1 : 0);
    }
    var data = builder.build();
    _expect_all(builder, trie.CodePointTrieKind.Fast);
    # 1024 index entries, the ASCII block, and one more block at most.
    expect_true(data.bytes.count < 1024 + 3 * 64);
}

[Test]
source_writes_a_constant_expression() {
    var builder = trie.CodePointTrieBuilder();
    builder.set('"' as uint, 0x22);
    builder.set('\\' as uint, 0x5C);
    builder.set(0x0A, 0x0A);
    var source = builder.build().source("u8");
    expect_true(source.starts_with("trie.CodePointTrie<u8>(\""));
    expect_true(source.contains("\\\""));
    expect_true(source.contains("\\\\"));
    expect_true(source.contains("\\x0A"));
    expect_false(source.contains("\n"));
    expect_true(source.ends_with(", 1, 1, 65536, 65536, 0, 1024)"));
}
