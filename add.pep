## Arithmetic in C: `add`, which `native/add.c` implements.

extern int mypkg_add(int a, int b);

## Returns `a + b`, computed by the C function `mypkg_add` in `native/add.c`.
##
## @param a the first number
## @param b the second number
## @returns their sum
## @example
##     mypkg.add(2, 3);   # 5
export add(a: int, b: int): int {
    return mypkg_add(a, b);
}
