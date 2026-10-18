# Boost.Context assembly

Unmodified ARM64 Mach-O `make_fcontext` and `jump_fcontext` from
[boostorg/context](https://github.com/boostorg/context), commit
`6ff80e0575133c6d0b704e03bbb956a0c3b9551a` (Boost 1.90.0).
The source copyright notices and Boost Software License 1.0 are preserved.
Only the context-switch assembly is used; the host adapter supplies stacks,
ownership checks, exception boundaries and floating-point environment handling.
