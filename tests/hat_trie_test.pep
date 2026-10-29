# HatTrie checked against the runtime's sorted Map.

import random;
import trie;

# A random key: a few bytes from a small alphabet, so keys share prefixes,
# with some multi-byte code points.
_random_key(generator: random.Generator): String {
    const LETTERS = "abcde\u{E9}\u{4E2D}";
    var out = StringBuilder();
    var size = generator.next_int(0..9);
    for (var i in 0..size) {
        out.append(LETTERS[generator.next_int(0..7) as ulong]);
    }
    return out.to_string();
}

# Every entry of `trie`, in order, is the entry of `expected` in the same place.
_expect_same(actual: trie.HatTrie<int>, expected: Map<String, int>) {
    expect_equal(actual.count, expected.count as ulong);
    var keys = Array<String>();
    var values = Array<int>();
    for (var (key, value) in actual) {
        keys.append(key);
        values.append(value);
    }
    expect_equal(keys.count, expected.count as ulong);
    ulong i = 0;
    var same = true;
    for (var (key, value) in expected) {
        if (i >= keys.count or keys[i] != key or values[i] != value) {
            same = false;
        }
        i += 1;
    }
    expect_true(same);
}

_expect_prefix(actual: trie.HatTrie<int>, expected: Map<String, int>, prefix: String) {
    var got = Array<String>();
    for (var (key, value) in actual.with_prefix(prefix)) {
        got.append(key);
        expect_equal(value, expected.get(key));
    }
    var want = Array<String>();
    for (var (key, value) in expected) {
        if (key.starts_with(prefix)) {
            want.append(key);
        }
    }
    expect_equal(got.count, want.count);
    var same = true;
    for (var i in 0..(got.count < want.count ? got.count : want.count)) {
        if (got[i] != want[i]) {
            same = false;
        }
    }
    expect_true(same);
}

[Test]
an_empty_trie_has_nothing() {
    var t = trie.HatTrie<int>();
    expect_equal(t.count, 0 as ulong);
    expect_false(t.contains(""));
    expect_equal(t.get("x"), 0);
    expect_false(t.remove("x"));
    expect_false(t.iterate().next());
    expect_false(t.with_prefix("a").next());
}

[Test]
the_empty_key_is_a_key() {
    for (var threshold in [4 as ulong, 16384 as ulong]) {
        var t = trie.HatTrie<int>(threshold);
        t[""] = 5;
        for (var i in 0..100) {
            t[$"k{i}"] = i;
        }
        expect_equal(t[""], 5);
        expect_true(t.contains(""));
        var first = t.iterate();
        expect_true(first.next());
        expect_equal(first.current().0, "");
        expect_true(t.remove(""));
        expect_false(t.contains(""));
        expect_equal(t.count, 100 as ulong);
    }
}

[Test]
insert_replaces_and_reports() {
    var t = trie.HatTrie<String>();
    expect_true(t.insert("a", "one"));
    expect_false(t.insert("a", "two"));
    expect_equal(t["a"], "two");
    expect_equal(t.count, 1 as ulong);
    expect_true(t.try_get("b").is_empty());
}

[Test]
random_keys_match_a_map() {
    for (var threshold in [4 as ulong, 64 as ulong, 16384 as ulong]) {
        var generator = random.Generator(threshold);
        var t = trie.HatTrie<int>(threshold);
        var expected = Map<String, int>();
        for (var step in 0..20000) {
            var key = _random_key(generator);
            if (generator.next_int(0..4) == 0) {
                expect_equal(t.remove(key), expected.remove(key));
            } else {
                expect_equal(t.insert(key, step), expected.insert(key, step));
            }
        }
        for (var (key, value) in expected) {
            expect_equal(t.get(key), value);
        }
        for (var i in 0..200) {
            var key = _random_key(generator);
            expect_equal(t.contains(key), expected.contains(key));
        }
        _expect_same(t, expected);
        for (var prefix in ["", "a", "ab", "abc", "\u{E9}", "\u{4E2D}a", "zz", "abcdeabcd"]) {
            _expect_prefix(t, expected, prefix);
        }
    }
}

[Test]
a_change_stops_an_iterator() {
    var t = trie.HatTrie<int>();
    t["a"] = 1;
    var it = t.iterate();
    expect_true(it.next());
    t["b"] = 2;
    expect_true(t.contains("b"));
}

[Test]
clear_empties_the_trie() {
    var t = trie.HatTrie<int>(4);
    for (var i in 0..1000) {
        t[$"{i}"] = i;
    }
    t.clear();
    expect_equal(t.count, 0 as ulong);
    expect_false(t.contains("5"));
    t["5"] = 5;
    expect_equal(t["5"], 5);
}
