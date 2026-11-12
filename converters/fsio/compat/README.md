# Windows filename matching

`fnmatch.c` and `fnmatch.h` derive from NetBSD's BSD-licensed implementation:

- https://raw.githubusercontent.com/NetBSD/src/trunk/lib/libc/gen/fnmatch.c
  (`fnmatch.c` revision 1.26, 2014-10-12), downloaded SHA-256
  `F4352F79A34CBDF2A2D1D6A34072B7F19EDA77E65FAC75E4CA42BDD56D2C000A`.
- https://raw.githubusercontent.com/NetBSD/src/trunk/include/fnmatch.h
  (`fnmatch.h` revision 1.13, 2011-01-31), downloaded SHA-256
  `4B5012AE56B40D56763BE3C046DA0CDAEA307C64A55E3BEC96F67E20BB821BA9`.

Downloaded 2026-11-12. Original bytes are retained in the local build evidence.
Local adaptations remove NetBSD libc namespace, feature-test and RCS machinery,
replace `_DIAGASSERT` with standard `assert`, and expose the implementation's
flags. Copyright and license notices remain in both files and are installed.
Only Windows builds use these files; Unix builds use the host's `fnmatch`.

This is byte-oriented matching for historical filesystem names: `*`, `?`,
bracket sets/ranges/negation, escaping, and leading-dot rules. Locale-dependent
character classes and Unicode collation are outside this Windows port's scope.
RT-11 maps its `%` wildcard to `?` and matches name and extension separately.
