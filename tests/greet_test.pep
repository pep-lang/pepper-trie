# The trie package's greetings.

import trie;

[Test]
greets_by_name() {
    expect_equal(trie.greet("Ada"), "Hello, Ada!");
}
