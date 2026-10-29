# Random keys for the HatTrieMap and HatTrieSet tests.

import random;

# A random key: a few bytes from a small alphabet, so keys share prefixes,
# with some multi-byte code points.
export random_key(generator: random.Generator): String {
    const LETTERS = "abcde\u{E9}\u{4E2D}";
    var out = StringBuilder();
    var size = generator.next_int(0..9);
    for (var i in 0..size) {
        out.append(LETTERS[generator.next_int(0..7) as ulong]);
    }
    return out.to_string();
}
