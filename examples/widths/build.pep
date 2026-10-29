# Builds the widths in ranges.txt into a StaticTrie, and writes it as the
# package's generated module: `generated.WIDTHS`.

import [File, Path] from io;
import os;
import trie;

main(): int {
    var builder = trie.StaticTrieBuilder(1);
    var text = File.read_to_string(Path("ranges.txt")).value();
    for (var line in text.lines()) {
        var fields = line.trim().split(" ");
        if (fields.count != 3 or line.starts_with("#")) {
            continue;
        }
        var first = uint.parse(fields[0], 16).value();
        var last = uint.parse(fields[1], 16).value();
        builder.set_range(first, last, uint.parse(fields[2], 16).value());
    }
    var source = builder.build(trie.StaticTrieKind.Small).source("u8");
    var out = Path(os.environment("PEP_OUT_DIR").value());
    File.write_text(out.join(Path("module.pep")), $"import trie;\n\nexport const WIDTHS = {source};\n");
    print("pep:rerun-if-changed=ranges.txt");
    return 0;
}
