# HatTrieSet checked against the runtime's sorted Set.

import random;
import trie;
import "keys";

_set_keys(actual: trie.HatTrieSet): String[] {
    var keys = Array<String>();
    for (var key in actual) {
        keys.append(key);
    }
    return keys;
}

_expect_set_prefix(actual: trie.HatTrieSet, expected: Set<String>, prefix: String) {
    var got = Array<String>();
    for (var key in actual.with_prefix(prefix)) {
        got.append(key);
    }
    var want = Array<String>();
    for (var key in expected) {
        if (key.starts_with(prefix)) {
            want.append(key);
        }
    }
    expect_equal("|".join(got), "|".join(want));
}

[Test]
an_empty_set_has_nothing() {
    var set = trie.HatTrieSet();
    expect_true(set.is_empty);
    expect_false(set.contains(""));
    expect_false(set.remove("x"));
    expect_false(set.iterate().next());
    expect_false(set.with_prefix("a").next());
}

[Test]
the_empty_string_is_a_member() {
    for (var threshold in [4 as ulong, 16384 as ulong]) {
        var set = trie.HatTrieSet(threshold);
        expect_true(set.insert(""));
        expect_false(set.insert(""));
        for (var i in 0..100) {
            set.insert($"k{i}");
        }
        expect_equal(_set_keys(set)[0], "");
        expect_true(set.remove(""));
        expect_false(set.contains(""));
        expect_equal(set.count, 100 as ulong);
    }
}

[Test]
random_strings_match_a_set() {
    for (var threshold in [4 as ulong, 64 as ulong, 16384 as ulong]) {
        var generator = random.Generator(threshold + 1);
        var set = trie.HatTrieSet(threshold);
        var expected = Set<String>();
        for (var step in 0..20000) {
            var key = random_key(generator);
            if (generator.next_int(0..4) == 0) {
                expect_equal(set.remove(key), expected.remove(key));
            } else {
                expect_equal(set.insert(key), expected.insert(key));
            }
        }
        expect_equal(set.count, expected.count as ulong);
        var want = Array<String>();
        for (var key in expected) {
            want.append(key);
        }
        expect_equal("|".join(_set_keys(set)), "|".join(want));
        for (var i in 0..200) {
            var key = random_key(generator);
            expect_equal(set.contains(key), expected.contains(key));
        }
        for (var prefix in ["", "a", "ab", "abc", "\u{E9}", "\u{4E2D}a", "zz"]) {
            _expect_set_prefix(set, expected, prefix);
        }
    }
}

[Test]
clear_empties_the_set() {
    var set = trie.HatTrieSet(4);
    for (var i in 0..1000) {
        set.insert($"{i}");
    }
    set.clear();
    expect_true(set.is_empty);
    expect_false(set.contains("5"));
}
