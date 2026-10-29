# The mypkg package's C code.

import mypkg;

[Test]
adds_in_c() {
    expect_equal(mypkg.add(2, 3), 5);
}
