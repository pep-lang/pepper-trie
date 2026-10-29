# Reads the widths the build script made into a StaticTrie constant.

import generated;

main(): int {
    assert(generated.WIDTHS.get('a' as uint) == 1, "ASCII is narrow");
    assert(generated.WIDTHS.get(0x4E2D) == 2, "CJK is wide");
    assert(generated.WIDTHS.get(0x301) == 0, "a combining mark takes no column");
    assert(generated.WIDTHS.get(0x20001) == 2, "so are the supplementary ideographs");
    print($"U+4E2D takes {generated.WIDTHS.get(0x4E2D)} columns");
    return 0;
}
