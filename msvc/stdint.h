// The real MSVC <stdint.h> defines its integer limit macros using Microsoft's
// non-standard `i8`/`i16`/`i32`/`i64`/`ui8`/`ui16`/`ui32`/`ui64`
// integer-literal suffixes, e.g.:
//
//   #define UINT64_MAX 0xffffffffffffffffui64
//
// Zig's `translate-c` in this snapshot uses its own self-hosted C
// frontend ("Aro"), not real Clang. Aro's normal lexer accepts these
// suffixes fine, but its *preprocessor conditional* (`#if`) expression
// evaluator does not, so any `#if` that expands one of these macros
// (e.g. wuffs's `#if SIZE_MAX < 0xFFFFFFFFFFFFFFFFull`) fails with
// "invalid suffix on integer constant" even though the same macro used
// outside a `#if` works fine.
//
// This is a real Zig/Aro incompleteness (MSVC's `#if`-expression grammar
// legitimately supports these suffixes; Aro's doesn't yet), not a bug in
// wuffs or in this repo. There's no way to route around it via `-D`
// command-line overrides because the real header re-defines these macros
// unconditionally on its own `#pragma once`-guarded inclusion, clobbering
// anything predefined beforehand.
//
// The fix: shadow the real header via an earlier `-I` search path entry
// (see build.zig, gated on `target.result.abi == .msvc`), pull in
// everything else from the real header via `#include_next`, then
// `#undef`/redefine just the handful of macros that use the offending
// suffixes with numerically-identical, standard-conforming ones
// (`ULL`/`LL`/plain-int, which Aro's `#if` evaluator has no trouble
// with). Macros that merely alias these (`INTPTR_MAX`, `PTRDIFF_MAX`,
// `SIG_ATOMIC_MAX`, etc.) don't need separate overrides since C macro
// expansion re-resolves nested references against whatever is currently
// defined at expansion time, not at the aliasing macro's own definition
// time.
#include_next <stdint.h>

#undef INT8_MIN
#define INT8_MIN (-127 - 1)
#undef INT16_MIN
#define INT16_MIN (-32767 - 1)
#undef INT32_MIN
#define INT32_MIN (-2147483647 - 1)
#undef INT64_MIN
#define INT64_MIN (-9223372036854775807LL - 1)

#undef INT8_MAX
#define INT8_MAX 127
#undef INT16_MAX
#define INT16_MAX 32767
#undef INT32_MAX
#define INT32_MAX 2147483647
#undef INT64_MAX
#define INT64_MAX 9223372036854775807LL

#undef UINT8_MAX
#define UINT8_MAX 0xffU
#undef UINT16_MAX
#define UINT16_MAX 0xffffU
#undef UINT32_MAX
#define UINT32_MAX 0xffffffffU
#undef UINT64_MAX
#define UINT64_MAX 0xffffffffffffffffULL

#undef SIZE_MAX
#ifdef _WIN64
#define SIZE_MAX 0xffffffffffffffffULL
#else
#define SIZE_MAX 0xffffffffU
#endif
